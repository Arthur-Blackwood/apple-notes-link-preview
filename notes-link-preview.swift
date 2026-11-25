import AppKit
import ApplicationServices

let apply = CommandLine.arguments.contains("--apply")
let system = AXUIElementCreateSystemWide()

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        e, name as CFString, &result
    ) == .success else { return nil }
    return result
}

func param(_ e: AXUIElement, _ name: String,
           _ range: NSRange) -> CFTypeRef? {
    var r = CFRange(location: range.location,
                    length: range.length)
    guard let v = AXValueCreate(.cfRange, &r)
    else { return nil }

    var result: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
        e, name as CFString, v, &result
    ) == .success else { return nil }
    return result
}

func stop(_ message: String) -> Never {
    print(message)
    exit(1)
}

func pause(_ seconds: Double = 0.4) {
    Thread.sleep(forTimeInterval: seconds)
}

func notesActive() -> Bool {
    NSWorkspace.shared.frontmostApplication?
        .bundleIdentifier == "com.apple.Notes"
}

func key(_ code: CGKeyCode) {
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil,
                virtualKey: code,
                keyDown: down)?.post(tap: .cghidEventTap)
    }
}

struct NoteLink {
    let range: NSRange
    let url: String
}

func scan(_ editor: AXUIElement) -> [NoteLink]? {
    let plain = attr(editor, "AXValue") as? String
    let count = (attr(editor, "AXNumberOfCharacters")
                 as? NSNumber)?.intValue
                 ?? plain?.utf16.count ?? 0

    guard count > 0 else { return nil }

    let rich = param(
        editor, "AXAttributedStringForRange",
        NSRange(location: 0, length: count)
    ) as? NSAttributedString

    guard let text = rich?.string ?? plain
    else { return nil }

    var links: [NoteLink] = []

    func add(_ range: NSRange, _ url: String) {
        guard url.hasPrefix("https://")
           || url.hasPrefix("http://")
        else { return }

        guard !links.contains(where: {
            NSIntersectionRange($0.range, range).length > 0
        }) else { return }

        links.append(NoteLink(range: range, url: url))
    }

    if let rich = rich {
        rich.enumerateAttributes(
            in: NSRange(location: 0, length: rich.length)
        ) { attributes, range, _ in
            for (k, v) in attributes {
                if ["NSLink", "AXLink", "AXLinkText"]
                    .contains(k.rawValue) {
                    if let url = v as? URL {
                        add(range, url.absoluteString)
                    } else if let url = v as? String {
                        add(range, url)
                    }
                }
            }
        }
    }

    // Fallback: detect visible raw URLs.
    if let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    ) {
        for match in detector.matches(
            in: text,
            range: NSRange(location: 0,
                           length: text.utf16.count)
        ) {
            if let url = match.url {
                add(match.range, url.absoluteString)
            }
        }
    }

    return links.sorted {
        $0.range.location > $1.range.location
    }
}

func menuItem(_ e: AXUIElement,
              depth: Int = 0) -> AXUIElement? {
    guard depth < 10 else { return nil }

    let role = attr(e, "AXRole") as? String ?? ""
    let title = attr(e, "AXTitle") as? String ?? ""

    if role == "AXMenuBar" { return nil }

    if role == "AXMenuItem",
       ["Show Link Preview", "显示链接预览", "顯示連結預覽"]
        .contains(title) {
        return e
    }

    for child in attr(e, "AXChildren")
        as? [AXUIElement] ?? [] {
        if let match = menuItem(child, depth: depth + 1) {
            return match
        }
    }

    return nil
}

func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, "AXPosition"),
          let s = attr(e, "AXSize"),
          CFGetTypeID(p) == AXValueGetTypeID(),
          CFGetTypeID(s) == AXValueGetTypeID()
    else { return nil }

    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
          AXValueGetValue(s as! AXValue, .cgSize, &size)
    else { return nil }

    return CGRect(origin: point, size: size)
}

func visibleFrame(_ editor: AXUIElement) -> CGRect? {
    guard var result = frame(editor) else { return nil }
    var current = editor

    for _ in 0..<15 {
        guard let raw = attr(current, "AXParent"),
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { break }

        current = raw as! AXUIElement

        let role = attr(current, "AXRole") as? String
        if role == "AXScrollArea" || role == "AXWindow" {
            if let bounds = frame(current) {
                result = result.intersection(bounds)
            }
        }
    }
    return result
}

func rightClick(_ point: CGPoint) {
    for type in [CGEventType.rightMouseDown,
                 CGEventType.rightMouseUp] {
        CGEvent(mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .right)?
            .post(tap: .cghidEventTap)
        pause(0.08)
    }
}

guard AXIsProcessTrusted() else {
    stop("Enable Accessibility permission for Terminal first.")
}

print(apply ? "APPLY MODE" : "DRY RUN — no note changes")
print("You have 5 seconds to click inside your note.")
pause(5)

guard notesActive() else {
    stop("Apple Notes is not active.")
}

guard let raw = attr(system, "AXFocusedUIElement"),
      CFGetTypeID(raw) == AXUIElementGetTypeID()
else { stop("Cannot find focused editor.") }

let editor = raw as! AXUIElement

guard attr(editor, "AXRole") as? String == "AXTextArea"
else { stop("Click inside the note body and try again.") }

guard let app = NSWorkspace.shared.frontmostApplication
else { stop("Cannot find Notes.") }

let notes = AXUIElementCreateApplication(app.processIdentifier)

guard let original = scan(editor)
else { stop("Cannot read note contents through Accessibility.") }

print("Detected \(original.count) candidate link(s).")
for link in original.reversed() {
    print("  \(link.url)")
}

if !apply {
    print("Dry run complete. Use --apply to convert.")
    exit(0)
}

var converted = 0

while true {
    guard notesActive() else {
        stop("Notes lost focus. Converted: \(converted)")
    }

    guard let links = scan(editor) else {
        stop("Cannot rescan note. Converted: \(converted)")
    }

    guard let link = links.first else { break }

    // Move the caret to the last remaining link.
    var selection = CFRange(
        location: link.range.location,
        length: 0
    )

    guard let value = AXValueCreate(.cfRange, &selection),
          AXUIElementSetAttributeValue(
            editor, "AXSelectedTextRange" as CFString, value
          ) == .success
    else { stop("Cannot position caret. Converted: \(converted)") }

    key(124) // Right arrow: move caret into view.
    pause(0.6)

    guard let rawBounds = param(
        editor, "AXBoundsForRange",
        NSRange(location: link.range.location, length: 1)
    ), CFGetTypeID(rawBounds) == AXValueGetTypeID()
    else { stop("Cannot locate link on screen.") }

    var bounds = CGRect.zero
    guard AXValueGetValue(
        rawBounds as! AXValue, .cgRect, &bounds
    ), !bounds.isEmpty
    else { stop("Invalid link bounds.") }

    let point = CGPoint(x: bounds.midX, y: bounds.midY)

    guard notesActive(),
          let visible = visibleFrame(editor),
          visible.contains(point)
    else { stop("Link is outside the visible editor.") }

    rightClick(point)
    pause(0.5)

    guard notesActive() else {
        stop("Notes lost focus.")
    }

    guard let item = menuItem(notes) else {
        key(53) // Escape
        stop("Show Link Preview not found. Converted: \(converted)")
    }

    guard AXUIElementPerformAction(
        item, "AXPress" as CFString
    ) == .success else {
        key(53)
        stop("Could not activate menu item.")
    }

    pause(1.2)

    guard let after = scan(editor),
          after.count < links.count
    else {
        stop("Could not verify conversion. Check the note manually.")
    }

    converted += 1
    print("Converted \(converted): \(link.url)")
}

print("Finished. Converted \(converted) link(s).")
