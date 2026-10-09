// ADR 0054 R5 frame gate: an MTKView rendering at 60 fps while a chunked
// 4k-token prefill runs on the same GPU; dropped frames = missing vsync
// draws vs the idle baseline. Gate: <10% dropped during the paced prefill.
//
// Usage: swift tool/frame_gate.swift <runner-binary> <pace_ms>
// Prints: {"baseline_fps": .., "during_fps": .., "dropped_pct": .., "ttft_ms": ..}

import AppKit
import MetalKit

let runner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "qwen_prefill_4k"
let pace = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "8"

final class Recorder: NSObject, MTKViewDelegate {
    var drawTimes: [Double] = []
    let start = CFAbsoluteTimeGetCurrent()
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        drawTimes.append(CFAbsoluteTimeGetCurrent() - start)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let device = MTLCreateSystemDefaultDevice() else {
    FileHandle.standardError.write(Data("no Metal device\n".utf8)); exit(2)
}

let rect = NSRect(x: 0, y: 0, width: 160, height: 120)
let view = MTKView(frame: rect, device: device)
view.preferredFramesPerSecond = 60
view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
let recorder = Recorder()
view.delegate = recorder

let window = NSWindow(
    contentRect: rect,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
window.contentView = view
window.orderFrontRegardless()

let process = Process()
process.executableURL = URL(fileURLWithPath: runner)
process.arguments = [pace]
var procEnd: Double? = nil
var procStart: Double = 0

let pipe = Pipe()
process.standardOutput = pipe
process.standardError = FileHandle.nullDevice
process.terminationHandler = { _ in
    procEnd = CFAbsoluteTimeGetCurrent() - recorder.start
}

// Phase timeline (seconds since start):
//   0.5–2.5  baseline (idle render)
//   2.5      spawn the prefill runner
//   exit     runner done (+0.5s settle) → report and exit
DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
    procStart = CFAbsoluteTimeGetCurrent() - recorder.start
    try? process.run()
}
var reported = false
Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
    if let end = procEnd, CFAbsoluteTimeGetCurrent() - recorder.start > end + 0.5, !reported {
        reported = true
        timer.invalidate()
        let draws = recorder.drawTimes
        func fps(_ from: Double, _ to: Double) -> Double {
            let n = draws.filter { $0 >= from && $0 < to }.count
            return Double(n) / max(to - from, 0.001)
        }
        let baseline = fps(0.5, 2.5)
        let during = fps(procStart, end)
        let dropped = baseline > 0 ? max(0, (1 - during / baseline)) * 100 : 100
        var ttft = -1.0
        if let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
           let out = String(data: data, encoding: .utf8),
           let line = out.split(separator: "\n").last,
           let obj = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: obj) as? [String: Any] {
            ttft = json["ttft_ms"] as? Double ?? -1
        }
        print(String(
            format: "{\"baseline_fps\": %.1f, \"during_fps\": %.1f, \"dropped_pct\": %.1f, \"ttft_ms\": %.1f, \"pace_ms\": %@}",
            baseline, during, dropped, ttft, pace))
        app.terminate(nil)
    }
}

app.run()
