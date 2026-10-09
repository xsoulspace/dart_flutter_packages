import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// C-ABI bridge for the macOS accessibility driver (ADR 0037 family).
// Every function is flat C: no Swift types cross the boundary.
//
// Coordinate convention: top-left relative screen coordinates everywhere
// (AXUIElementCopyElementAtPosition's documented system, identical to
// CGEvent mouse coordinates — no conversion on either side).
//
// Error codes: 0 ok · 1 invalid argument · 2 no focused application ·
// 3 AX api error · 4 no element at position · 5 unknown element handle ·
// 6 driver closed · 7 app not found · 8 activation/launch/terminate
// failed · 10 accessibility permission missing.

/// Element handles resolved during the last snapshot / hit-test. Reset on
/// every new observation so stale ids fail closed (code 5) instead of
/// acting on re-purposed memory.
private final class ElementRegistry {
    var elements: [AXUIElement] = []
    private let lock = NSLock()

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        elements.removeAll()
    }

    func add(_ element: AXUIElement) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        elements.append(element)
        return Int32(elements.count - 1)
    }

    func get(_ id: Int32) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        guard id >= 0, Int(id) < elements.count else { return nil }
        return elements[Int(id)]
    }
}

private let registry = ElementRegistry()

// Sub-tick scroll accumulator (per direction), cleared by release_all.
private var scrollRemainderX = 0.0
private var scrollRemainderY = 0.0

private func strdupOut(_ string: String, _ out: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
    guard let out else { return 1 }
    out.pointee = strdup(string)
    return 0
}

/// Maps an AX role string onto the family's lowercase semantic roles.
private func semanticRole(_ axRole: String?) -> String {
    switch axRole {
    case "AXButton": return "button"
    case "AXCheckBox": return "checkbox"
    case "AXRadioButton": return "radio"
    case "AXSwitch": return "switch"
    case "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox":
        return "textbox"
    case "AXStaticText": return "text"
    case "AXHeading": return "heading"
    case "AXImage": return "image"
    case "AXLink": return "link"
    case "AXSlider": return "slider"
    case "AXProgressIndicator": return "progress"
    case "AXPopUpButton", "AXMenuButton": return "popupbutton"
    case "AXMenu", "AXMenuBar": return "menu"
    case "AXMenuItem", "AXMenuBarItem": return "menuitem"
    case "AXWindow", "AXDialog", "AXFloatingWindow": return "window"
    case "AXSheet": return "sheet"
    case "AXTabGroup": return "tabgroup"
    case "AXTable": return "table"
    case "AXRow": return "row"
    case "AXCell": return "cell"
    case "AXList": return "list"
    case "AXScrollArea": return "scrollarea"
    case "AXToolbar": return "toolbar"
    case "AXApplication": return "application"
    default: return "generic"
    }
}

/// Accessible name: AXDescription first (buttons/fields carry user-visible
/// labels there), then AXTitle.
private func accessibleName(_ element: AXUIElement) -> String? {
    for attribute in [kAXDescriptionAttribute as String, kAXTitleAttribute as String] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw as? String,
              !value.isEmpty
        else { continue }
        return value
    }
    return nil
}

private func accessibleValue(_ element: AXUIElement) -> String? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success
    else { return nil }
    if let string = raw as? String { return string }
    if let number = raw as? NSNumber { return number.stringValue }
    return nil
}

private func accessibleBounds(_ element: AXUIElement) -> [String: Double]? {
    var positionRaw: CFTypeRef?
    var sizeRaw: CFTypeRef?
    guard
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRaw) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success,
        let positionRaw, let sizeRaw
    else { return nil }
    let position = positionRaw as! AXValue
    let size = sizeRaw as! AXValue
    guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize
    else { return nil }
    var point = CGPoint.zero
    var frame = CGSize.zero
    AXValueGetValue(position, .cgPoint, &point)
    AXValueGetValue(size, .cgSize, &frame)
    return [
        "left": Double(point.x),
        "top": Double(point.y),
        "width": Double(frame.width),
        "height": Double(frame.height),
    ]
}

/// Serializes one element (no recursion). Registers a fresh handle so
/// actions can address it later.
private func nodeDict(_ element: AXUIElement) -> [String: Any] {
    let roleRaw = optionalStringAttribute(element, kAXRoleAttribute as String)
    var node: [String: Any] = ["role": semanticRole(roleRaw)]
    if let name = accessibleName(element) { node["name"] = name }
    if let value = accessibleValue(element) { node["value"] = value }
    if let bounds = accessibleBounds(element) { node["bounds"] = bounds }
    node["attributes"] = ["axid": String(registry.add(element))]
    return node
}

private func optionalStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
          let value = raw as? String
    else { return nil }
    return value
}

/// Depth-bounded walk of the element subtree into JSON-shaped dicts.
private func walkTree(
    _ element: AXUIElement,
    depth: Int,
    maxDepth: Int,
    budget: inout Int
) -> [String: Any] {
    var node = nodeDict(element)
    if depth < maxDepth, budget > 0 {
        var childrenRaw: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRaw
        ) == .success, let children = childrenRaw as? [AXUIElement] {
            var childNodes: [[String: Any]] = []
            for child in children where budget > 0 {
                budget -= 1
                childNodes.append(walkTree(child, depth: depth + 1, maxDepth: maxDepth, budget: &budget))
            }
            if !childNodes.isEmpty { node["children"] = childNodes }
        }
    }
    return node
}

private func systemWide() -> AXUIElement {
    ensureAppRegistered()
    return AXUIElementCreateSystemWide()
}

/// CLI processes get kAXErrorFailure (-25204) on AX element queries until
/// they register with the window server; touching NSApplication.shared
/// (with .prohibited activation — no Dock icon, no runloop needed)
/// registers the process. Idempotent.
private var appRegistered = false
private func ensureAppRegistered() {
    if appRegistered { return }
    appRegistered = true
    _ = NSApplication.shared
    NSApplication.shared.setActivationPolicy(.prohibited)
}

@_cdecl("xs_axdrv_version")
public func xs_axdrv_version() -> UnsafePointer<CChar>? {
    // Deliberate one-time leak of a short constant; callers never free it.
    let copy = strdup("xs-ax-driver/1")
    return UnsafePointer(copy)
}

@_cdecl("xs_axdrv_ax_trusted")
public func xs_axdrv_ax_trusted() -> Bool {
    AXIsProcessTrusted()
}

/// Prompts with the system Accessibility consent dialog when untrusted.
@_cdecl("xs_axdrv_request_trust")
public func xs_axdrv_request_trust() -> Bool {
    AXIsProcessTrustedWithOptions(
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    )
}

/// Serializes the focused application's accessibility tree to JSON
/// (malloc'd, freed by the caller via `xs_axdrv_free`).
@_cdecl("xs_axdrv_snapshot_json")
public func xs_axdrv_snapshot_json(
    _ maxDepth: Int32,
    _ maxNodes: Int32,
    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    guard let outJson, maxDepth > 0, maxNodes > 0 else { return 1 }
    guard AXIsProcessTrusted() else { return 10 }
    registry.reset()
    var raw: CFTypeRef?
    let code = AXUIElementCopyAttributeValue(
        systemWide(), kAXFocusedApplicationAttribute as CFString, &raw
    )
    guard code == .success, let app = raw as! AXUIElement? else {
        // Raw negative AXError code; 2 reserved for "nothing focused".
        return code == .cannotComplete ? 3 : (code == .noValue ? 2 : Int32(code.rawValue))
    }
    var budget = Int(maxNodes) - 1
    let tree = walkTree(app, depth: 0, maxDepth: Int(maxDepth), budget: &budget)
    guard let data = try? JSONSerialization.data(withJSONObject: tree),
          let json = String(data: data, encoding: .utf8)
    else { return 3 }
    return strdupOut(json, outJson)
}

/// Hit-tests the element at (x, y) across all applications and serializes
/// it (single node, no recursion) to JSON.
@_cdecl("xs_axdrv_element_at_position_json")
public func xs_axdrv_element_at_position_json(
    _ x: Double,
    _ y: Double,
    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    guard let outJson else { return 1 }
    guard AXIsProcessTrusted() else { return 10 }
    registry.reset()
    var raw: AXUIElement?
    let code = AXUIElementCopyElementAtPosition(systemWide(), Float(x), Float(y), &raw)
    guard code == .success, let element = raw else {
        return code == .noValue ? 4 : Int32(code.rawValue)
    }
    let node = nodeDict(element)
    guard let data = try? JSONSerialization.data(withJSONObject: node),
          let json = String(data: data, encoding: .utf8)
    else { return 3 }
    return strdupOut(json, outJson)
}

private func resolvedElement(_ handle: Int32) -> AXUIElement? {
    registry.get(handle)
}

/// Performs the AXPress action on the element with [handle].
@_cdecl("xs_axdrv_press")
public func xs_axdrv_press(_ handle: Int32) -> Int32 {
    guard let element = resolvedElement(handle) else { return 5 }
    let code = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if code == .success { return 0 }
    if code == .actionUnsupported || code == .attributeUnsupported { return 3 }
    return 3
}

/// Makes the element the focused control (keyboard target for typing).
@_cdecl("xs_axdrv_focus")
public func xs_axdrv_focus(_ handle: Int32) -> Int32 {
    guard let element = resolvedElement(handle) else { return 5 }
    let code = AXUIElementSetAttributeValue(
        element, kAXFocusedAttribute as CFString, kCFBooleanTrue
    )
    return code == .success ? 0 : 3
}

@_cdecl("xs_axdrv_type_text")
public func xs_axdrv_type_text(_ text: UnsafePointer<CChar>?) -> Int32 {
    guard let text else { return 1 }
    let value = String(cString: text)
    guard !value.isEmpty else { return 0 }
    let units = Array(value.utf16)
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
    units.withUnsafeBufferPointer { buffer in
        event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buffer.baseAddress)
    }
    guard let event else { return 3 }
    event.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)?
        .post(tap: .cghidEventTap)
    return 0
}

/// Logical key names → CG virtual keycodes (HIServices layout-independent
/// subset; letters/digits are US-layout positions, same convention the
/// Vosges desktop host uses).
private func keyCode(for rawKey: String) -> UInt16? {
    switch rawKey.uppercased() {
    case "ENTER", "RETURN": return 36
    case "TAB": return 48
    case "ESCAPE", "ESC": return 53
    case "BACKSPACE": return 51
    case "DELETE": return 117
    case "SPACE": return 49
    case "ARROWUP", "UP": return 126
    case "ARROWDOWN", "DOWN": return 125
    case "ARROWLEFT", "LEFT": return 123
    case "ARROWRIGHT", "RIGHT": return 124
    case "A": return 0
    case "S": return 1
    case "D": return 2
    case "F": return 3
    case "H": return 4
    case "G": return 5
    case "Z": return 6
    case "X": return 7
    case "C": return 8
    case "V": return 9
    case "B": return 11
    case "Q": return 12
    case "W": return 13
    case "E": return 14
    case "R": return 15
    case "Y": return 16
    case "T": return 17
    case "1": return 18
    case "2": return 19
    case "3": return 20
    case "4": return 21
    case "6": return 22
    case "5": return 23
    case "9": return 25
    case "7": return 26
    case "8": return 28
    case "0": return 29
    case "O": return 31
    case "U": return 32
    case "I": return 34
    case "P": return 35
    case "L": return 37
    case "J": return 38
    case "K": return 40
    case "N": return 45
    case "M": return 46
    // Modifier names (the family chord vocabulary, ADR 0053).
    case "SHIFT": return 56
    case "CONTROL", "CTRL": return 59
    case "ALT", "OPTION": return 58
    case "META", "COMMAND", "CMD": return 55
    default: return nil
    }
}

/// CGEventFlags raw value for a family modifier name; 0 outside it.
private func cgModifierFlag(_ name: String) -> Int64 {
    switch name.lowercased() {
    case "shift": return 0x020000 // .maskShift
    case "control", "ctrl": return 0x040000 // .maskControl
    case "alt", "option": return 0x080000 // .maskAlternate
    case "meta", "command", "cmd", "windows": return 0x100000 // .maskCommand
    default: return 0
    }
}

@_cdecl("xs_axdrv_key_press")
public func xs_axdrv_key_press(_ key: UnsafePointer<CChar>?) -> Int32 {
    guard let key else { return 1 }
    guard let code = keyCode(for: String(cString: key)) else { return 1 }
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?
        .post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?
        .post(tap: .cghidEventTap)
    return 0
}

/// One scroll bundle in wheel lines; dy > 0 scrolls up, dx > 0 scrolls
/// right. Sub-line fractions accumulate per direction until a whole line
/// accrues (per-frame gesture deltas are fractional).
@_cdecl("xs_axdrv_scroll")
public func xs_axdrv_scroll(_ dx: Double, _ dy: Double) -> Int32 {
    scrollRemainderX += dx
    scrollRemainderY += dy
    let linesX = Int(scrollRemainderX.rounded(.towardZero))
    let linesY = Int(scrollRemainderY.rounded(.towardZero))
    scrollRemainderX -= Double(linesX)
    scrollRemainderY -= Double(linesY)
    guard linesX != 0 || linesY != 0 else { return 0 }
    guard let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .line,
        wheelCount: linesX != 0 ? 2 : 1,
        wheel1: Int32(clamping: linesY),
        wheel2: Int32(clamping: linesX),
        wheel3: 0
    ) else { return 3 }
    event.post(tap: .cghidEventTap)
    return 0
}

// MARK: - Coordinate pointer verbs (ADR 0053). CGEvent synthesis for
// clickAt/moveTo/drag, matching the type/key/scroll event tap above.

/// Pointer buttons currently held down (0 left, 1 right, 2 middle).
/// Moves dispatch as dragged events while any is set, so a carried drag
/// looks like a gesture, not a hover.
private var pointerButtonsDown: Set<Int> = []
private var lastPointerX = 0.0
private var lastPointerY = 0.0

private func cgButton(_ name: String) -> CGMouseButton? {
    switch name.lowercased() {
    case "left": return .left
    case "right": return .right
    case "middle": return .center
    default: return nil
    }
}

private func mouseDownType(_ button: CGMouseButton) -> CGEventType {
    switch button {
    case .left: return .leftMouseDown
    case .right: return .rightMouseDown
    default: return .otherMouseDown
    }
}

private func mouseUpType(_ button: CGMouseButton) -> CGEventType {
    switch button {
    case .left: return .leftMouseUp
    case .right: return .rightMouseUp
    default: return .otherMouseUp
    }
}

private func postMouseEvent(
    _ type: CGEventType,
    at x: Double,
    _ y: Double,
    button: CGMouseButton,
    clicks: Int64,
    flags: Int64
) -> Int32 {
    guard let event = CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: CGPoint(x: x, y: y),
        mouseButton: button
    ) else { return 3 }
    event.setIntegerValueField(.mouseEventClickState, value: clicks)
    if flags != 0 {
        event.flags = CGEventFlags(rawValue: UInt64(bitPattern: flags))
    }
    event.post(tap: .cghidEventTap)
    return 0
}

/// Moves the pointer to (x, y). While a button is logically down the
/// event is the matching dragged type (drag continuation); otherwise a
/// plain move. [modifierFlags] is the raw CGEventFlags mask for an
/// active chord (shift 0x020000, control 0x040000, alt 0x080000,
/// command 0x100000).
@_cdecl("xs_axdrv_pointer_move")
public func xs_axdrv_pointer_move(
    _ x: Double,
    _ y: Double,
    _ modifierFlags: Int64
) -> Int32 {
    guard AXIsProcessTrusted() else { return 10 }
    let (type, button): (CGEventType, CGMouseButton)
    if pointerButtonsDown.contains(0) {
        (type, button) = (.leftMouseDragged, .left)
    } else if pointerButtonsDown.contains(1) {
        (type, button) = (.rightMouseDragged, .right)
    } else if pointerButtonsDown.contains(2) {
        (type, button) = (.otherMouseDragged, .center)
    } else {
        (type, button) = (.mouseMoved, .left)
    }
    let code = postMouseEvent(
        type,
        at: x,
        y,
        button: button,
        clicks: 1,
        flags: modifierFlags
    )
    if code == 0 {
        lastPointerX = x
        lastPointerY = y
    }
    return code
}

/// Presses or releases [button] (`left`/`right`/`middle`) at (x, y).
/// clickCount 1-3 becomes the event's click state so the host's
/// double/triple-click recognition fires; [modifierFlags] carries an
/// active chord.
@_cdecl("xs_axdrv_pointer_button")
public func xs_axdrv_pointer_button(
    _ x: Double,
    _ y: Double,
    _ buttonName: UnsafePointer<CChar>?,
    _ down: Bool,
    _ clickCount: Int32,
    _ modifierFlags: Int64
) -> Int32 {
    guard let buttonName, let button = cgButton(String(cString: buttonName)) else {
        return 1
    }
    guard AXIsProcessTrusted() else { return 10 }
    let clicks = Int64(max(1, min(3, clickCount)))
    let code = postMouseEvent(
        down ? mouseDownType(button) : mouseUpType(button),
        at: x,
        y,
        button: button,
        clicks: clicks,
        flags: modifierFlags
    )
    guard code == 0 else { return code }
    let id = button == .left ? 0 : (button == .right ? 1 : 2)
    if down {
        pointerButtonsDown.insert(id)
    } else {
        pointerButtonsDown.remove(id)
    }
    lastPointerX = x
    lastPointerY = y
    return 0
}

@_cdecl("xs_axdrv_key_down")
public func xs_axdrv_key_down(_ key: UnsafePointer<CChar>?) -> Int32 {
    guard let key else { return 1 }
    let name = String(cString: key)
    guard let code = keyCode(for: name) else { return 1 }
    guard let event = CGEvent(
        keyboardEventSource: nil,
        virtualKey: code,
        keyDown: true
    ) else { return 3 }
    // A modifier key event announces its own flag so subsequent events
    // (and the HID state) see the chord forming.
    let flag = cgModifierFlag(name)
    if flag != 0 {
        event.flags = CGEventFlags(rawValue: UInt64(bitPattern: flag))
    }
    event.post(tap: .cghidEventTap)
    return 0
}

@_cdecl("xs_axdrv_key_up")
public func xs_axdrv_key_up(_ key: UnsafePointer<CChar>?) -> Int32 {
    guard let key else { return 1 }
    guard let code = keyCode(for: String(cString: key)) else { return 1 }
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?
        .post(tap: .cghidEventTap)
    return 0
}

/// Drops every cached element handle and scroll fraction. Called on
/// session teardown and driver close. Best-effort releases any
/// logically-down pointer button at its last position, so a truncated
/// gesture cannot leave the host with a stuck button.
@_cdecl("xs_axdrv_release_all")
public func xs_axdrv_release_all() {
    for id in pointerButtonsDown {
        let button: CGMouseButton
        let type: CGEventType
        switch id {
        case 0:
            button = .left
            type = .leftMouseUp
        case 1:
            button = .right
            type = .rightMouseUp
        default:
            button = .center
            type = .otherMouseUp
        }
        _ = postMouseEvent(
            type,
            at: lastPointerX,
            lastPointerY,
            button: button,
            clicks: 1,
            flags: 0
        )
    }
    pointerButtonsDown.removeAll()
    registry.reset()
    scrollRemainderX = 0
    scrollRemainderY = 0
}

/// One PNG encode with an optional long-side downscale (`maxPx` > 0
/// caps the image budget agents receive; mcp_flutter's ~1024px
/// convention). 3 = destination failed, 4 = encode failed,
/// 5 = allocation failed.
private func encodePng(
    _ image: CGImage,
    _ maxPx: Int32,
    _ outData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outLen: UnsafeMutablePointer<Int>?
) -> Int32 {
    var finalImage = image
    if maxPx > 0 {
        finalImage = downscaled(image, maxPx) ?? image
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, "public.png" as CFString, 1, nil
    ) else { return 3 }
    CGImageDestinationAddImage(destination, finalImage, nil)
    guard CGImageDestinationFinalize(destination) else { return 4 }
    let length = data.length
    guard let buffer = malloc(length) else { return 5 }
    memcpy(buffer, data.bytes, length)
    outData?.pointee = buffer.assumingMemoryBound(to: UInt8.self)
    outLen?.pointee = length
    return 0
}

/// High-quality long-side downscale through a bitmap context.
private func downscaled(_ image: CGImage, _ maxPx: Int32) -> CGImage? {
    let maxSide = CGFloat(max(maxPx, 1))
    let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
    if scale >= 1 { return image }
    let targetW = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let targetH = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard let context = CGContext(
        data: nil,
        width: targetW,
        height: targetH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: targetW, height: targetH)
    )
    return context.makeImage()
}

/// Captures one PNG frame of [displayId] (0 = main display) into a
/// malloc'd buffer the caller frees with `xs_axdrv_free`. Requires screen
/// recording permission: 10 = permission missing, 2 = image failed,
/// then the encode table.
@_cdecl("xs_axdrv_screenshot_png")
public func xs_axdrv_screenshot_png(
    _ displayId: UInt32,
    _ maxPx: Int32,
    _ outData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outLen: UnsafeMutablePointer<Int>?
) -> Int32 {
    guard let outData, let outLen else { return 1 }
    guard CGPreflightScreenCaptureAccess() else { return 10 }
    let target = displayId == 0 ? CGMainDisplayID() : CGDirectDisplayID(displayId)
    guard let image = CGDisplayCreateImage(target) else { return 2 }
    return encodePng(image, maxPx, outData, outLen)
}

/// Captures one PNG frame of a single [windowId] — the window-scoped
/// capture display shots cannot do (occlusion included, exact window
/// bounds). Requires screen recording permission: 10 = permission
/// missing, 2 = image failed (unknown window), then the encode table.
@_cdecl("xs_axdrv_screenshot_window_png")
public func xs_axdrv_screenshot_window_png(
    _ windowId: UInt32,
    _ maxPx: Int32,
    _ outData: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ outLen: UnsafeMutablePointer<Int>?
) -> Int32 {
    guard let outData, let outLen else { return 1 }
    guard CGPreflightScreenCaptureAccess() else { return 10 }
    guard let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(windowId),
        [.bestResolution]
    ) else { return 2 }
    return encodePng(image, maxPx, outData, outLen)
}

/// Serializes the on-screen, normal-layer windows owned by [pid]
/// (0 = every regular app) to JSON:
/// `[{windowId, pid, name, bounds{left,top,width,height}}, ...]`.
/// Window ids and bounds need no consent; titles may be empty without
/// Screen Recording.
@_cdecl("xs_axdrv_windows_json")
public func xs_axdrv_windows_json(
    _ pid: Int32,
    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    guard let outJson else { return 1 }
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        as? [[String: Any]]
    else { return 3 }
    var windows: [[String: Any]] = []
    for info in list {
        let owner = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
        if pid != 0 && owner != pid { continue }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        if layer != 0 { continue } // normal-level windows only
        let windowId = info[kCGWindowNumber as String] as? Int ?? 0
        guard windowId != 0 else { continue }
        var dict: [String: Any] = [
            "windowId": windowId,
            "pid": Int(owner),
            "name": info[kCGWindowName as String] as? String ?? "",
        ]
        if let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
           let x = bounds["X"]?.doubleValue,
           let y = bounds["Y"]?.doubleValue,
           let width = bounds["Width"]?.doubleValue,
           let height = bounds["Height"]?.doubleValue {
            dict["bounds"] = [
                "left": x, "top": y, "width": width, "height": height,
            ]
        }
        windows.append(dict)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: windows),
          let json = String(data: data, encoding: .utf8)
    else { return 3 }
    return strdupOut(json, outJson)
}

@_cdecl("xs_axdrv_free")
public func xs_axdrv_free(_ pointer: UnsafeMutableRawPointer?) {
    free(pointer)
}

// MARK: - App management (the macOS rung: manage APPLICATIONS, not only
// the focused one — discover what is running, activate it, launch by
// bundle id, terminate, and snapshot ANY app's tree, not just the
// focused one).

/// Serializes one NSRunningApplication into a JSON dict.
private func appDict(_ app: NSRunningApplication) -> [String: Any] {
    var dict: [String: Any] = [
        "pid": app.processIdentifier,
        "name": app.localizedName ?? "",
        "active": app.isActive,
        "hidden": app.isHidden,
    ]
    if let bundleId = app.bundleIdentifier {
        dict["bundleId"] = bundleId
    }
    return dict
}

private func runningRegularApps() -> [NSRunningApplication] {
    ensureAppRegistered()
    return NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular
    }
}

/// Serializes the running regular (Dock-able) applications to JSON:
/// `[{pid, bundleId, name, active, hidden}, ...]`.
@_cdecl("xs_axdrv_apps_json")
public func xs_axdrv_apps_json(
    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    guard let outJson else { return 1 }
    let apps = runningRegularApps().map(appDict)
    guard let data = try? JSONSerialization.data(withJSONObject: apps),
          let json = String(data: data, encoding: .utf8)
    else { return 3 }
    return strdupOut(json, outJson)
}

/// Serializes the frontmost application to JSON (same shape as one
/// element of `xs_axdrv_apps_json`).
@_cdecl("xs_axdrv_frontmost_json")
public func xs_axdrv_frontmost_json(
    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    guard let outJson else { return 1 }
    ensureAppRegistered()
    guard let app = NSWorkspace.shared.frontmostApplication else { return 2 }
    guard let data = try? JSONSerialization.data(withJSONObject: appDict(app)),
          let json = String(data: data, encoding: .utf8)
    else { return 3 }
    return strdupOut(json, outJson)
}

/// Brings the application with [pid] to the front. 0 ok · 7 unknown pid ·
/// 8 activation refused.
@_cdecl("xs_axdrv_activate_app")
public func xs_axdrv_activate_app(_ pid: Int32) -> Int32 {
    ensureAppRegistered()
    guard let app = NSRunningApplication(processIdentifier: pid) else { return 7 }
    // `activate` without options is the post-macOS-14 API; the options
    // variant stays for older hosts. Either failing falls back to
    // unhiding, which is the common reason an activation "did nothing".
    if app.activate() { return 0 }
    if app.activate(options: []) { return 0 }
    if app.unhide() { return 0 }
    return 8
}

/// Launches (or activates) the app with [bundleId]; returns the new (or
/// existing) pid. 0 = newly launched pid, negative = error: -7 unknown
/// bundle id, -8 launch failed.
@_cdecl("xs_axdrv_launch_app")
public func xs_axdrv_launch_app(_ bundleId: UnsafePointer<CChar>?) -> Int32 {
    guard let bundleId else { return -1 }
    ensureAppRegistered()
    let id = String(cString: bundleId)
    // Already running? Activation IS the launch (the borrowed-lease rule).
    if let running = NSWorkspace.shared.runningApplications
        .first(where: { $0.bundleIdentifier == id }) {
        _ = running.activate()
        return Int32(running.processIdentifier)
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
        return -7
    }
    let configuration = NSWorkspace.OpenConfiguration()
    let launched = DispatchSemaphore(value: 0)
    var launchError: Error?
    NSWorkspace.shared.openApplication(
        at: url, configuration: configuration
    ) { app, error in
        launchError = error
        launched.signal()
    }
    launched.wait()
    if launchError != nil { return -8 }
    // The completion hands the app back on newer macOS; scan as the
    // portable fallback (the app may also have been adopted mid-launch).
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == id }) {
            return Int32(app.processIdentifier)
        }
        usleep(100_000)
    }
    return -8
}

/// Asks the application with [pid] to terminate (graceful, like choosing
/// Quit). 0 ok · 7 unknown pid · 8 refused.
@_cdecl("xs_axdrv_terminate_app")
public func xs_axdrv_terminate_app(_ pid: Int32) -> Int32 {
    ensureAppRegistered()
    guard let app = NSRunningApplication(processIdentifier: pid) else { return 7 }
    return app.terminate() ? 0 : 8
}

/// Serializes ANY application's accessibility tree (by pid) to JSON —
/// the per-app observation the focused-app-only snapshot could not do.
/// `xs_axdrv_snapshot_json` remains the focused-app shorthand.
@_cdecl("xs_axdrv_snapshot_app_json")
public func xs_axdrv_snapshot_app_json(
    _ maxDepth: Int32,
    _ maxNodes: Int32,
    _ pid: Int32,
    _ outJson: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 {
    guard let outJson, maxDepth > 0, maxNodes > 0, pid > 0 else { return 1 }
    guard AXIsProcessTrusted() else { return 10 }
    registry.reset()
    let app = AXUIElementCreateApplication(pid)
    // A pid that is gone (or not an AX-capable app) surfaces as
    // attributeUnsupported / noValue; map the obvious ones to 7.
    var raw: CFTypeRef?
    let roleCode = AXUIElementCopyAttributeValue(
        app, kAXRoleAttribute as CFString, &raw
    )
    if roleCode == .attributeUnsupported || roleCode == .noValue {
        return 7
    }
    var budget = Int(maxNodes) - 1
    let tree = walkTree(app, depth: 0, maxDepth: Int(maxDepth), budget: &budget)
    guard let data = try? JSONSerialization.data(withJSONObject: tree),
          let json = String(data: data, encoding: .utf8)
    else { return 3 }
    return strdupOut(json, outJson)
}
