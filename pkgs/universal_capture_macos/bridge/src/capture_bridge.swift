import CoreGraphics
import ApplicationServices
import Foundation

// C-ABI bridge for pure-Dart callers (see ADR 0037 / ADR 0001).
// Every function is flat C: no Swift types cross the boundary.

@_cdecl("xs_capture_bridge_version")
public func xs_capture_bridge_version() -> UnsafePointer<CChar>? {
    // Deliberate one-time leak of a short constant; callers never free it.
    let copy = strdup("xs-capture-bridge/1")
    return UnsafePointer(copy)
}

@_cdecl("xs_capture_ax_is_trusted")
public func xs_capture_ax_is_trusted() -> Bool {
    return AXIsProcessTrusted()
}

@_cdecl("xs_capture_screen_permission_preflight")
public func xs_capture_screen_permission_preflight() -> Bool {
    return CGPreflightScreenCaptureAccess()
}

/// Prompts the user with the system screen-recording consent dialog.
/// Never call this from tests; it is an explicit user-consent action.
@_cdecl("xs_capture_screen_permission_request")
public func xs_capture_screen_permission_request() -> Bool {
    return CGRequestScreenCaptureAccess()
}

@_cdecl("xs_capture_list_displays")
public func xs_capture_list_displays(
    _ outIds: UnsafeMutablePointer<UInt32>?,
    _ maxCount: Int32,
    _ outCount: UnsafeMutablePointer<Int32>?
) -> Int32 {
    guard let outIds, let outCount, maxCount > 0 else { return 1 }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxCount))
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(UInt32(maxCount), &ids, &count) == .success else {
        return 2
    }
    for index in 0..<Int(count) {
        outIds[index] = ids[index]
    }
    outCount.pointee = Int32(count)
    return 0
}

/// Captures one frame of [displayId] (0 = main display) as PNG bytes
/// into a malloc'd buffer the caller frees with `xs_capture_free`.
/// Returns 0 on success, or an error code:
/// 2 = display image failed, 3 = destination failed, 4 = encode failed,
/// 5 = allocation failed, 10 = screen recording permission missing.
@_cdecl("xs_capture_screenshot_png")
public func xs_capture_screenshot_png(
    _ displayId: UInt32,
    _ outData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outLen: UnsafeMutablePointer<Int>?
) -> Int32 {
    guard let outData, let outLen else { return 1 }
    guard CGPreflightScreenCaptureAccess() else { return 10 }
    let target = displayId == 0 ? CGMainDisplayID() : CGDirectDisplayID(displayId)
    guard let image = CGDisplayCreateImage(target) else { return 2 }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, "public.png" as CFString, 1, nil
    ) else { return 3 }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return 4 }
    let length = data.length
    guard let buffer = malloc(length) else { return 5 }
    memcpy(buffer, data.bytes, length)
    outData.pointee = buffer.assumingMemoryBound(to: UInt8.self)
    outLen.pointee = length
    return 0
}

@_cdecl("xs_capture_free")
public func xs_capture_free(_ pointer: UnsafeMutableRawPointer?) {
    free(pointer)
}

// MARK: - ScreenCaptureKit streaming (continuous frames)

import ScreenCaptureKit
import CoreMedia
import CoreVideo
import VideoToolbox

private final class StreamBox {
    let stream: SCStream
    let delegate: StreamDelegate
    init(stream: SCStream, delegate: StreamDelegate) {
        self.stream = stream
        self.delegate = delegate
    }
}

/// Delivers JPEG-encoded display frames to a Dart `NativeCallable.listener`.
private final class StreamDelegate: NSObject, SCStreamOutput, SCStreamDelegate {
    let callback: @convention(c) (
        UnsafePointer<UInt8>?, Int32, Int64, UnsafeMutableRawPointer?
    ) -> Void
    let userData: UnsafeMutableRawPointer?

    init(
        callback: @convention(c) (
            UnsafePointer<UInt8>?, Int32, Int64, UnsafeMutableRawPointer?
        ) -> Void,
        userData: UnsafeMutableRawPointer?
    ) {
        self.callback = callback
        self.userData = userData
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        var imageOut: CGImage?
        let vtStatus = VTCreateCGImageFromCVPixelBuffer(
            pixelBuffer, options: nil, imageOut: &imageOut
        )
        guard vtStatus == noErr, let image = imageOut else { return }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.7]
                as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return }
        let seconds = CMSampleBufferGetPresentationTimeStamp(
            sampleBuffer
        ).seconds
        let timestampUs = Int64(seconds.isFinite ? seconds * 1_000_000 : 0)
        callback(
            data.bytes.assumingMemoryBound(to: UInt8.self),
            Int32(data.length),
            timestampUs,
            userData
        )
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Dart observes the end of the frame stream on stop(); a failure
        // mid-stream surfaces as stream termination, not a callback.
    }
}

private var nextStreamHandle: Int32 = 1
private var liveStreams: [Int32: StreamBox] = [:]

private final class Int32Box {
    var value: Int32 = 0
}

/// Starts a continuous ScreenCaptureKit stream of [displayId]
/// (0 = first available display), delivering JPEG frames at up to
/// [maxFps] fps through [callback]. Returns a positive stream handle on
/// success, or an error code: 10 = permission missing, 2 = no displays,
/// 3 = stream setup failed. Stop with `xs_capture_stream_stop`.
@_cdecl("xs_capture_stream_start")
public func xs_capture_stream_start(
    _ displayId: UInt32,
    _ maxFps: Int32,
    _ callback: @convention(c) (
        UnsafePointer<UInt8>?, Int32, Int64, UnsafeMutableRawPointer?
    ) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32 {
    guard CGPreflightScreenCaptureAccess() else { return 10 }
    let box = Int32Box()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let content = try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let displays = content.displays
            guard !displays.isEmpty else {
                box.value = 2
                semaphore.signal()
                return
            }
            let display = displayId == 0
                ? displays[0]
                : (displays.first { $0.displayID == displayId }
                    ?? displays[0])
            let filter = SCContentFilter(
                display: display, excludingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.minimumFrameInterval = CMTime(
                value: 1, timescale: CMTimeScale(max(maxFps, 1))
            )
            configuration.queueDepth = 3
            configuration.showsCursor = true
            configuration.width = max(640, min(1920, display.width))
            configuration.height = max(360, min(1080, display.height))
            let delegate = StreamDelegate(
                callback: callback, userData: userData
            )
            let stream = SCStream(
                filter: filter,
                configuration: configuration,
                delegate: delegate
            )
            try stream.addStreamOutput(
                delegate,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "xs.capture.stream")
            )
            try await stream.startCapture()
            let handle = nextStreamHandle
            nextStreamHandle += 1
            liveStreams[handle] = StreamBox(
                stream: stream, delegate: delegate
            )
            box.value = handle
        } catch {
            box.value = 3
        }
        semaphore.signal()
    }
    semaphore.wait()
    return box.value
}

/// Stops and releases a stream started by `xs_capture_stream_start`.
@_cdecl("xs_capture_stream_stop")
public func xs_capture_stream_stop(_ handle: Int32) -> Int32 {
    guard let box = liveStreams.removeValue(forKey: handle) else {
        return 1
    }
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        try? await box.stream.stopCapture()
        semaphore.signal()
    }
    semaphore.wait()
    return 0
}
