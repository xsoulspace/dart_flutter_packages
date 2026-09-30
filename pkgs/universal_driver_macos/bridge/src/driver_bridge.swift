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
// 6 driver closed · 10 accessibility permission missing.

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
    default: return nil
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

/// Drops every cached element handle and scroll fraction. Called on
/// session teardown and driver close.
@_cdecl("xs_axdrv_release_all")
public func xs_axdrv_release_all() {
    registry.reset()
    scrollRemainderX = 0
    scrollRemainderY = 0
}

/// Captures one PNG frame of [displayId] (0 = main display) into a
/// malloc'd buffer the caller frees with `xs_axdrv_free`. Requires screen
/// recording permission: 10 = permission missing, 2 = image failed,
/// 3 = destination failed, 4 = encode failed, 5 = allocation failed.
@_cdecl("xs_axdrv_screenshot_png")
public func xs_axdrv_screenshot_png(
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

@_cdecl("xs_axdrv_free")
public func xs_axdrv_free(_ pointer: UnsafeMutableRawPointer?) {
    free(pointer)
}
