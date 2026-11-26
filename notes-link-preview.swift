import AppKit
import ApplicationServices

let apply = CommandLine.arguments.contains("--apply")
let normalizeMixed = !CommandLine.arguments.contains("--no-normalize-mixed")
let system = AXUIElementCreateSystemWide()

let showPreviewMenuTitles: Set<String> = [
    "Show Link Preview",
    "显示链接预览",
    "顯示連結預覽"
]

let editLinkMenuTitles: Set<String> = [
    "Edit Link",
    "编辑链接",
    "編輯連結"
]

let okButtonTitles: Set<String> = [
    "OK", "Done", "Save",
    "好", "确定", "確定", "完成"
]

let cancelButtonTitles: Set<String> = [
    "Cancel", "取消"
]

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

func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: code,
            keyDown: down
        ) else { continue }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        if !flags.isEmpty {
            pause(0.03)
        }
    }
}

func pasteWithPreservedClipboard(_ text: String) -> Bool {
    let pb = NSPasteboard.general
    var savedItems: [[NSPasteboard.PasteboardType: Data]] = []

    for item in pb.pasteboardItems ?? [] {
        var entry: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) {
                entry[type] = data
            }
        }
        if !entry.isEmpty {
            savedItems.append(entry)
        }
    }

    pb.clearContents()
    guard pb.setString(text, forType: .string) else { return false }

    key(0, flags: .maskCommand) // Cmd+A
    pause(0.08)
    key(9, flags: .maskCommand) // Cmd+V
    pause(0.18)

    pb.clearContents()
    if !savedItems.isEmpty {
        let restored = savedItems.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(restored)
    }

    return true
}

struct NoteLink {
    let range: NSRange
    let url: String
    let hasVerifiedURL: Bool
}

// V11: mixed-script detection and URL normalization helpers
enum ScriptBucket {
    case latinOrDigit
    case cjk
    case emoji
    case otherNonLatin
}

func scriptBuckets(in text: String) -> Set<ScriptBucket> {
    var buckets = Set<ScriptBucket>()

    for scalar in text.unicodeScalars {
        let v = scalar.value

        // Ignore whitespace, control characters, and combining marks.
        if CharacterSet.whitespacesAndNewlines.contains(scalar)
            || CharacterSet.controlCharacters.contains(scalar)
            || CharacterSet.nonBaseCharacters.contains(scalar)
            || v == 0x200D || v == 0xFE0E || v == 0xFE0F {
            continue
        }

        if (0x41...0x5A).contains(v)
            || (0x61...0x7A).contains(v)
            || (0x30...0x39).contains(v)
            || (0x00C0...0x024F).contains(v) {
            buckets.insert(.latinOrDigit)
        } else if (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2FA1F).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0x3040...0x309F).contains(v)
            || (0x30A0...0x30FF).contains(v)
            || (0x31F0...0x31FF).contains(v)
            || (0xFF65...0xFF9F).contains(v)
            || (0xAC00...0xD7AF).contains(v)
            || (0x1100...0x11FF).contains(v)
            || (0x3130...0x318F).contains(v)
            || (0x3100...0x312F).contains(v) {
            buckets.insert(.cjk)
        } else if scalar.properties.isEmojiPresentation {
            buckets.insert(.emoji)
        } else if !scalar.isASCII && CharacterSet.letters.contains(scalar) {
            buckets.insert(.otherNonLatin)
        }
    }

    return buckets
}

func isMixedScript(_ text: String) -> Bool {
    scriptBuckets(in: text).count >= 2
}

func asciiNormalizedURL(_ raw: String) -> String {
    if raw.unicodeScalars.allSatisfy(\.isASCII) {
        return raw
    }

    var result = ""
    for scalar in raw.unicodeScalars {
        if scalar.isASCII {
            result.unicodeScalars.append(scalar)
        } else {
            for byte in String(scalar).utf8 {
                result += String(format: "%%%02X", byte)
            }
        }
    }
    return result
}

func canonicalURLString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let encoded = asciiNormalizedURL(trimmed)

    guard var comps = URLComponents(string: encoded) else {
        return encoded
    }

    comps.scheme = comps.scheme?.lowercased()
    comps.host = comps.host?.lowercased()

    if comps.path == "/" && comps.query == nil && comps.fragment == nil {
        comps.path = ""
    }

    return comps.string ?? encoded
}

func urlsEquivalent(_ a: String, _ b: String) -> Bool {
    let ta = a.trimmingCharacters(in: .whitespacesAndNewlines)
    let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
    if ta == tb { return true }
    if asciiNormalizedURL(ta) == asciiNormalizedURL(tb) { return true }
    return canonicalURLString(ta) == canonicalURLString(tb)
}

func needsLinkNormalization(_ targetText: String, link: NoteLink) -> Bool {
    guard link.hasVerifiedURL else { return false }
    if targetText == asciiNormalizedURL(link.url) {
        return false
    }
    return isMixedScript(targetText)
}

func mergeAdjacentSameURLLinks(_ links: [NoteLink]) -> [NoteLink] {
    let ascending = links.sorted { $0.range.location < $1.range.location }
    var merged: [NoteLink] = []

    for link in ascending {
        if let last = merged.last,
           last.hasVerifiedURL && link.hasVerifiedURL,
           last.url == link.url,
           NSMaxRange(last.range) == link.range.location {
            let combined = NSUnionRange(last.range, link.range)
            merged[merged.count - 1] = NoteLink(
                range: combined,
                url: last.url,
                hasVerifiedURL: true
            )
        } else {
            merged.append(link)
        }
    }

    return merged
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

    func add(_ range: NSRange, _ url: String, verified: Bool = true) {
        guard url.hasPrefix("https://")
           || url.hasPrefix("http://")
        else { return }

        guard !links.contains(where: {
            NSIntersectionRange($0.range, range).length > 0
        }) else { return }

        links.append(NoteLink(
            range: range,
            url: url,
            hasVerifiedURL: verified
        ))
    }

    print("DEBUG: Plain text length:", plain?.utf16.count ?? -1)
    print("DEBUG: Character count:", count)
    print("DEBUG: Attributed text length:", rich?.length ?? -1)

    var keys = Set<String>()
    rich?.enumerateAttributes(
        in: NSRange(location: 0, length: rich?.length ?? 0)
    ) { attributes, _, _ in
        for k in attributes.keys {
            keys.insert(k.rawValue)
        }
    }

    print("DEBUG: Attribute keys:", keys.sorted())

    if let data = param(
        editor, "AXRTFForRange",
        NSRange(location: 0, length: count)
    ) as? Data,
       let rtf = try? NSAttributedString(
           data: data,
           options: [.documentType:
                       NSAttributedString.DocumentType.rtf],
           documentAttributes: nil
       ) {
        print("DEBUG: RTF length:", rtf.length)

        if rtf.string == text {
            rtf.enumerateAttribute(
                .link,
                in: NSRange(location: 0, length: rtf.length)
            ) { value, range, _ in
                if let url = value as? URL {
                    add(range, url.absoluteString, verified: true)
                } else if let url = value as? String {
                    add(range, url, verified: true)
                }
            }
        }
    } else {
        print("DEBUG: RTF unavailable")
    }

    if let rich = rich {
        rich.enumerateAttributes(
            in: NSRange(location: 0, length: rich.length)
        ) { attributes, range, _ in
            for (k, v) in attributes {
                if ["NSLink", "AXLink", "AXLinkText"]
                    .contains(k.rawValue) {
                    if let url = v as? URL {
                        add(range, url.absoluteString, verified: true)
                    } else if let url = v as? String {
                        add(range, url, verified: true)
                    }
                }
            }
        }
    }

    // V4: detect links directly from AXLink ranges.
    if let rich = rich {
        let full = NSRange(location: 0, length: rich.length)

        rich.enumerateAttribute(
            NSAttributedString.Key("AXLink"),
            in: full
        ) { value, range, _ in
            guard let value = value,
                  !(value is NSNull),
                  range.length > 0
            else { return }

            if let flag = value as? NSNumber,
               !flag.boolValue {
                return
            }

            var attachment = false

            rich.enumerateAttribute(
                NSAttributedString.Key("AXAttachment"),
                in: range
            ) { item, _, _ in
                if let item = item, !(item is NSNull) {
                    attachment = true
                }
            }

            guard !attachment else { return }

            guard !links.contains(where: {
                NSIntersectionRange($0.range, range).length > 0
            }) else { return }

            let label = (rich.string as NSString)
                .substring(with: range)

            guard !label.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            !label.contains("\u{FFFC}")
            else { return }

            print("DEBUG: AXLink type:",
                  String(describing: type(of: value)))
            print("DEBUG: AXLink range:",
                  range.location, range.length)

            // V8: stable URL identity
            var identity = label
            var verifiedURL = false

            let raw = value as CFTypeRef

            if CFGetTypeID(raw) == AXUIElementGetTypeID() {
                let element = raw as! AXUIElement

                if let target = attr(element, "AXURL") {
                    if let url = target as? URL {
                        identity = url.absoluteString
                        verifiedURL = identity.hasPrefix("http://")
                            || identity.hasPrefix("https://")
                    } else if let url = target as? String,
                              !url.isEmpty {
                        identity = url
                        verifiedURL = identity.hasPrefix("http://")
                            || identity.hasPrefix("https://")
                    }
                }
            } else if let url = value as? URL {
                identity = url.absoluteString
                verifiedURL = identity.hasPrefix("http://")
                    || identity.hasPrefix("https://")
            } else if let url = value as? String,
                      url.hasPrefix("http://") || url.hasPrefix("https://") {
                identity = url
                verifiedURL = true
            }

            links.append(NoteLink(
                range: range,
                url: identity,
                hasVerifiedURL: verifiedURL
            ))
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
                add(match.range, url.absoluteString, verified: true)
            }
        }
    }

    let merged = mergeAdjacentSameURLLinks(links)

    return merged.sorted {
        $0.range.location > $1.range.location
    }
}

// V10: inline link protection
func noteText(_ editor: AXUIElement) -> NSString? {
    guard let count = (attr(editor, "AXNumberOfCharacters")
        as? NSNumber)?.intValue, count > 0
    else { return nil }

    guard let rich = param(
        editor, "AXAttributedStringForRange",
        NSRange(location: 0, length: count)
    ) as? NSAttributedString
    else { return nil }

    return rich.string as NSString
}

func selectedRange(_ editor: AXUIElement) -> NSRange? {
    guard let raw = attr(editor, "AXSelectedTextRange"),
          CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }

    var range = CFRange(location: 0, length: 0)

    guard AXValueGetValue(raw as! AXValue, .cfRange, &range)
    else { return nil }

    return NSRange(location: range.location, length: range.length)
}

func selectLink(_ editor: AXUIElement, _ range: NSRange) -> Bool {
    var selection = CFRange(
        location: range.location,
        length: range.length
    )

    guard let value = AXValueCreate(.cfRange, &selection),
          AXUIElementSetAttributeValue(
              editor, "AXSelectedTextRange" as CFString, value
          ) == .success
    else { return false }

    pause(0.25)
    return selectedRange(editor) == range
}

func isInlineLink(_ text: NSString, _ range: NSRange) -> Bool {
    let line = text.lineRange(for: range)

    let before = text.substring(with: NSRange(
        location: line.location,
        length: range.location - line.location
    ))

    let after = text.substring(with: NSRange(
        location: NSMaxRange(range),
        length: NSMaxRange(line) - NSMaxRange(range)
    ))

    let prefix = before.trimmingCharacters(
        in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "•◦▪-")
        )
    )

    return !prefix.isEmpty ||
        !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

func normalizedMenuTitle(_ title: String) -> String {
    var s = title.trimmingCharacters(in: .whitespacesAndNewlines)
    while s.hasSuffix("…") || s.hasSuffix(".") {
        s.removeLast()
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

func findMenuItem(_ e: AXUIElement,
                  matching targets: Set<String>,
                  depth: Int = 0,
                  trace: Bool = false) -> AXUIElement? {
    guard depth < 10 else { return nil }

    let role = attr(e, "AXRole") as? String ?? ""
    let title = attr(e, "AXTitle") as? String ?? ""

    if role == "AXMenuBar" { return nil }

    // V7: menu diagnostics
    if trace && role == "AXMenuItem" {
        print("MENU: " + title)
    }

    if role == "AXMenuItem",
       targets.contains(normalizedMenuTitle(title)) {
        return e
    }

    for child in attr(e, "AXChildren")
        as? [AXUIElement] ?? [] {
        if let match = findMenuItem(
            child, matching: targets,
            depth: depth + 1, trace: trace
        ) {
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

func parentWindow(_ element: AXUIElement) -> AXUIElement? {
    var current = element
    for _ in 0..<20 {
        if attr(current, "AXRole") as? String == "AXWindow" {
            return current
        }
        guard let raw = attr(current, "AXParent"),
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { break }
        current = raw as! AXUIElement
    }
    return nil
}

// V9: native mouse events
func rightClick(_ point: CGPoint, control: Bool = false) {
    let source = CGEventSource(stateID: .hidSystemState)

    let button: CGMouseButton = control ? .left : .right

    let downType: CGEventType =
        control ? .leftMouseDown : .rightMouseDown

    let upType: CGEventType =
        control ? .leftMouseUp : .rightMouseUp

    CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    )?.post(tap: .cghidEventTap)

    pause(0.15)

    guard notesActive() else { return }

    for type in [downType, upType] {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }

        event.setIntegerValueField(
            .mouseEventClickState, value: 1
        )

        event.flags = control ? .maskControl : []

        event.post(tap: .cghidEventTap)
        pause(0.08)
    }
}

func leftClick(_ point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)

    CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    )?.post(tap: .cghidEventTap)

    pause(0.1)

    guard notesActive() else { return }

    for type in [CGEventType.leftMouseDown, CGEventType.leftMouseUp] {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        event.setIntegerValueField(
            .mouseEventClickState, value: 1
        )

        event.post(tap: .cghidEventTap)
        pause(0.06)
    }
}

func openLinkContextMenu(
    editor: AXUIElement,
    notes: AXUIElement,
    link: NoteLink,
    selectCompleteRange: Bool,
    targetTitles: Set<String>
) -> AXUIElement? {
    let offsets = [
        link.range.length / 2,
        min(2, max(0, link.range.length - 1)),
        link.range.length * 3 / 4,
        0
    ]

    var attempted = Set<Int>()

    for offset in offsets {
        guard notesActive() else {
            stop("Notes lost focus.")
        }

        guard attempted.insert(offset).inserted
        else { continue }

        let location = link.range.location + offset

        func visiblePoint() -> CGPoint? {
            guard let rawBounds = param(
                editor,
                "AXBoundsForRange",
                NSRange(location: location, length: 1)
            ),
            CFGetTypeID(rawBounds) == AXValueGetTypeID()
            else { return nil }

            var bounds = CGRect.zero

            guard AXValueGetValue(
                rawBounds as! AXValue,
                .cgRect,
                &bounds
            ), !bounds.isEmpty
            else { return nil }

            let point = CGPoint(
                x: bounds.midX,
                y: bounds.midY
            )

            guard let visible = visibleFrame(editor),
                  visible.contains(point)
            else { return nil }

            return point
        }

        // Do not change the caret if the link is visible.
        if visiblePoint() == nil {
            var selection = CFRange(
                location: location,
                length: 0
            )

            guard let value = AXValueCreate(
                .cfRange, &selection
            ),
            AXUIElementSetAttributeValue(
                editor,
                "AXSelectedTextRange" as CFString,
                value
            ) == .success
            else { continue }

            pause(0.6)

            // Keyboard scrolling only as a fallback.
            if visiblePoint() == nil {
                key(124)
                pause(0.9)
            }
        }

        guard notesActive() else {
            stop("Notes lost focus.")
        }

        if selectCompleteRange {
            guard selectLink(editor, link.range)
            else {
                print("Could not select complete link.")
                continue
            }
        }

        guard let point = visiblePoint()
        else { continue }

        let control = attempted.count % 2 == 0

        print(control
            ? "Click method: Control-click"
            : "Click method: Right-click")

        rightClick(point, control: control)

        var foundItem: AXUIElement?
        for _ in 0..<8 {
            pause(0.3)

            guard notesActive() else {
                stop("Notes lost focus.")
            }

            if let item = findMenuItem(notes, matching: targetTitles) {
                foundItem = item
                break
            }
        }

        if let item = foundItem {
            if selectCompleteRange && selectedRange(editor) != link.range {
                print("Selection changed — retrying safely.")
                key(53)
                pause(0.3)
                continue
            }
            return item
        }

        print("Inspecting context menu...")
        _ = findMenuItem(notes, matching: targetTitles, trace: true)

        key(53)
        pause(0.3)

        print("Retrying another link position...")
    }

    return nil
}

// V11: Edit Link dialog inspection, editing, and recovery
struct EditLinkDialog {
    let container: AXUIElement
    let urlField: AXUIElement
    let nameField: AXUIElement
    let okButton: AXUIElement?
    let cancelButton: AXUIElement?
}

func axStringValue(_ element: AXUIElement) -> String {
    (attr(element, "AXValue") as? String) ?? ""
}

func axBool(_ element: AXUIElement, _ name: String) -> Bool? {
    if let b = attr(element, name) as? Bool { return b }
    if let n = attr(element, name) as? NSNumber { return n.boolValue }
    return nil
}

func collectDialogContainers(
    from root: AXUIElement,
    depth: Int = 0,
    into result: inout [AXUIElement]
) {
    guard depth < 8 else { return }
    let role = attr(root, "AXRole") as? String ?? ""
    if role == "AXMenuBar" || role == "AXTextArea" { return }

    if role == "AXSheet" || role == "AXPopover" {
        if !result.contains(where: { CFEqual($0, root) }) {
            result.append(root)
        }
    }

    for child in attr(root, "AXChildren") as? [AXUIElement] ?? [] {
        collectDialogContainers(from: child, depth: depth + 1, into: &result)
    }
}

func candidateDialogContainers(
    notes: AXUIElement,
    editorWin: AXUIElement?
) -> [AXUIElement] {
    var containers: [AXUIElement] = []

    var roots: [AXUIElement] = []
    if let focused = attr(notes, "AXFocusedWindow"),
       CFGetTypeID(focused) == AXUIElementGetTypeID() {
        roots.append(focused as! AXUIElement)
    }
    if let main = attr(notes, "AXMainWindow"),
       CFGetTypeID(main) == AXUIElementGetTypeID() {
        let w = main as! AXUIElement
        if !roots.contains(where: { CFEqual($0, w) }) {
            roots.append(w)
        }
    }
    for w in attr(notes, "AXWindows") as? [AXUIElement] ?? [] {
        if !roots.contains(where: { CFEqual($0, w) }) {
            roots.append(w)
        }
    }

    for w in roots {
        collectDialogContainers(from: w, into: &containers)

        let subrole = attr(w, "AXSubrole") as? String ?? ""
        let isEditorWin = editorWin.map { CFEqual($0, w) } ?? false
        if !isEditorWin
            || subrole == "AXDialog"
            || subrole == "AXSheet"
            || subrole == "AXFloatingWindow" {
            if !containers.contains(where: { CFEqual($0, w) }) {
                containers.append(w)
            }
        }
    }

    return containers
}

func collectDialogControls(
    from element: AXUIElement,
    depth: Int = 0,
    fields: inout [AXUIElement],
    buttons: inout [AXUIElement]
) {
    guard depth < 12 else { return }
    let role = attr(element, "AXRole") as? String ?? ""
    if role == "AXMenuBar" || role == "AXTextArea" { return }

    if role == "AXTextField" || role == "AXComboBox" {
        if !fields.contains(where: { CFEqual($0, element) }) {
            fields.append(element)
        }
        return
    }

    if role == "AXButton" {
        if !buttons.contains(where: { CFEqual($0, element) }) {
            buttons.append(element)
        }
    }

    for child in attr(element, "AXChildren") as? [AXUIElement] ?? [] {
        collectDialogControls(
            from: child, depth: depth + 1,
            fields: &fields, buttons: &buttons
        )
    }
}

func fieldHintText(_ field: AXUIElement) -> String {
    let parts = [
        attr(field, "AXPlaceholderValue") as? String,
        attr(field, "AXDescription") as? String,
        attr(field, "AXTitle") as? String,
        attr(field, "AXIdentifier") as? String
    ].compactMap { $0 }
    return parts.joined(separator: " ").lowercased()
}

func disambiguateTwoURLFields(_ a: AXUIElement, _ b: AXUIElement)
    -> (urlField: AXUIElement, nameField: AXUIElement)? {
    let roleA = attr(a, "AXRole") as? String ?? ""
    let roleB = attr(b, "AXRole") as? String ?? ""

    if roleA == "AXComboBox" && roleB == "AXTextField" {
        return (a, b)
    }
    if roleB == "AXComboBox" && roleA == "AXTextField" {
        return (b, a)
    }

    let hintA = fieldHintText(a)
    let hintB = fieldHintText(b)
    let nameHints = ["optional", "name", "可选", "可選", "名称", "名稱"]
    let aLooksLikeName = nameHints.contains { hintA.contains($0) }
    let bLooksLikeName = nameHints.contains { hintB.contains($0) }

    if bLooksLikeName && !aLooksLikeName { return (a, b) }
    if aLooksLikeName && !bLooksLikeName { return (b, a) }

    if let fa = frame(a), let fb = frame(b), abs(fa.minY - fb.minY) > 4 {
        return fa.minY < fb.minY ? (a, b) : (b, a)
    }

    return nil
}

func findEditLinkDialog(
    notes: AXUIElement,
    editorWin: AXUIElement?,
    expectedURL: String,
    expectedName: String,
    allowEmptyName: Bool,
    trace: Bool = false
) -> EditLinkDialog? {
    let containers = candidateDialogContainers(
        notes: notes, editorWin: editorWin
    )

    for container in containers {
        var fields: [AXUIElement] = []
        var buttons: [AXUIElement] = []
        collectDialogControls(
            from: container, fields: &fields, buttons: &buttons
        )

        if trace {
            let role = attr(container, "AXRole") as? String ?? ""
            print("DEBUG: Dialog container \(role) fields=\(fields.count) buttons=\(buttons.count)")
            for (idx, f) in fields.enumerated() {
                let fRole = attr(f, "AXRole") as? String ?? ""
                print("DEBUG:   field[\(idx)] \(fRole) value=\"\(axStringValue(f))\" hint=\"\(fieldHintText(f))\"")
            }
            for b in buttons {
                let title = attr(b, "AXTitle") as? String ?? ""
                print("DEBUG:   button \"\(title)\" enabled=\(axBool(b, "AXEnabled") ?? true)")
            }
        }

        guard fields.count >= 2 else { continue }

        let urlMatches = fields.filter {
            urlsEquivalent(axStringValue($0), expectedURL)
        }

        var matchedURLField: AXUIElement?
        var matchedNameField: AXUIElement?

        if urlMatches.count == 1 {
            let candidateURL = urlMatches[0]
            let otherFields = fields.filter { !CFEqual($0, candidateURL) }
            let nameMatches = otherFields.filter { field in
                let val = axStringValue(field)
                return val == expectedName
                    || (allowEmptyName && val.isEmpty)
            }
            if nameMatches.count == 1 {
                matchedURLField = candidateURL
                matchedNameField = nameMatches[0]
            }
        } else if urlMatches.count == 2
                    && urlsEquivalent(expectedName, expectedURL) {
            if let pair = disambiguateTwoURLFields(
                urlMatches[0], urlMatches[1]
            ) {
                matchedURLField = pair.urlField
                matchedNameField = pair.nameField
            }
        }

        guard let urlField = matchedURLField,
              let nameField = matchedNameField,
              axBool(nameField, "AXEnabled") != false
        else { continue }

        var okButton: AXUIElement?
        if let rawDefault = attr(container, "AXDefaultButton"),
           CFGetTypeID(rawDefault) == AXUIElementGetTypeID() {
            okButton = (rawDefault as! AXUIElement)
        }
        if okButton == nil {
            okButton = buttons.first { button in
                let title = (attr(button, "AXTitle") as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return okButtonTitles.contains(title)
            }
        }

        let cancelButton = buttons.first { button in
            let title = (attr(button, "AXTitle") as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cancelButtonTitles.contains(title)
        }

        return EditLinkDialog(
            container: container,
            urlField: urlField,
            nameField: nameField,
            okButton: okButton,
            cancelButton: cancelButton
        )
    }

    return nil
}

func isElementOrDescendantFocused(
    _ element: AXUIElement,
    in notes: AXUIElement
) -> Bool {
    if axBool(element, "AXFocused") == true { return true }
    guard let rawFocused = attr(notes, "AXFocusedUIElement"),
          CFGetTypeID(rawFocused) == AXUIElementGetTypeID()
    else { return false }

    var current = rawFocused as! AXUIElement
    for _ in 0..<6 {
        if CFEqual(current, element) { return true }
        guard let parent = attr(current, "AXParent"),
              CFGetTypeID(parent) == AXUIElementGetTypeID()
        else { break }
        current = parent as! AXUIElement
    }
    return false
}

func focusDialogField(
    _ field: AXUIElement,
    dialog: EditLinkDialog,
    notes: AXUIElement
) -> Bool {
    _ = AXUIElementSetAttributeValue(
        field, "AXFocused" as CFString, kCFBooleanTrue
    )
    pause(0.12)

    if isElementOrDescendantFocused(field, in: notes) {
        return true
    }

    if let fieldRect = frame(field), !fieldRect.isEmpty {
        let center = CGPoint(x: fieldRect.midX, y: fieldRect.midY)
        if let dialogRect = frame(dialog.container),
           dialogRect.contains(center) {
            leftClick(center)
            pause(0.15)
        }
    }

    return isElementOrDescendantFocused(field, in: notes)
}

func dismissDialog(_ dialog: EditLinkDialog?) {
    if let cancel = dialog?.cancelButton,
       AXUIElementPerformAction(cancel, "AXPress" as CFString) == .success {
        pause(0.3)
        return
    }
    key(53)
    pause(0.3)
}

func hasOpenEditLinkDialog(
    notes: AXUIElement,
    editorWin: AXUIElement?,
    expectedURL: String
) -> Bool {
    let containers = candidateDialogContainers(
        notes: notes, editorWin: editorWin
    )

    for container in containers {
        var fields: [AXUIElement] = []
        var buttons: [AXUIElement] = []
        collectDialogControls(
            from: container, fields: &fields, buttons: &buttons
        )
        if fields.count >= 2 && fields.contains(where: {
            urlsEquivalent(axStringValue($0), expectedURL)
        }) {
            return true
        }
    }

    return false
}

func setDialogFieldValue(
    _ field: AXUIElement,
    dialog: EditLinkDialog,
    notes: AXUIElement,
    expectedURL: String,
    to newValue: String
) -> Bool {
    guard notesActive() else { return false }
    guard urlsEquivalent(axStringValue(dialog.urlField), expectedURL) else {
        return false
    }

    let focused = focusDialogField(field, dialog: dialog, notes: notes)

    // 1. Prefer AXSelectedText replacement on the focused field editor,
    // which fires AppKit/SwiftUI change notifications without IME issues.
    if focused {
        let currentLength = axStringValue(field).utf16.count
        var fullRange = CFRange(location: 0, length: currentLength)
        if let rangeValue = AXValueCreate(.cfRange, &fullRange),
           AXUIElementSetAttributeValue(
               field, "AXSelectedTextRange" as CFString, rangeValue
           ) == .success,
           AXUIElementSetAttributeValue(
               field, "AXSelectedText" as CFString, newValue as CFTypeRef
           ) == .success {
            pause(0.15)
        }
    }

    // 2. Fallback to clipboard-preserving Cmd+A + Cmd+V on the verified focused field.
    if axStringValue(field) != newValue {
        if focused || focusDialogField(field, dialog: dialog, notes: notes) {
            guard notesActive() else { return false }
            _ = pasteWithPreservedClipboard(newValue)
        }
    }

    // 3. Final fallback to direct AXValue assignment.
    if axStringValue(field) != newValue {
        _ = AXUIElementSetAttributeValue(
            field, "AXValue" as CFString, newValue as CFTypeRef
        )
        pause(0.15)
    }

    guard axStringValue(field) == newValue else {
        print("DEBUG: Name field readback mismatch: \"\(axStringValue(field))\"")
        return false
    }

    // Confirm the URL field remained untouched.
    guard urlsEquivalent(axStringValue(dialog.urlField), expectedURL) else {
        print("DEBUG: URL field changed unexpectedly!")
        return false
    }

    return true
}

func renameLinkTitle(
    editor: AXUIElement,
    notes: AXUIElement,
    editorWin: AXUIElement?,
    link: NoteLink,
    targetIndex: Int,
    expectedLabels: [String],
    beforeText: NSString,
    expectedCurrentName: String,
    newName: String,
    allowEmptyName: Bool
) -> NoteLink? {
    guard NSMaxRange(link.range) <= beforeText.length else { return nil }

    let beforePrefix = beforeText.substring(to: link.range.location)
    let beforeSuffix = beforeText.substring(from: NSMaxRange(link.range))
    let expectedAfterText = beforePrefix + newName + beforeSuffix

    guard let editItem = openLinkContextMenu(
        editor: editor,
        notes: notes,
        link: link,
        selectCompleteRange: true,
        targetTitles: editLinkMenuTitles
    ) else {
        print("Could not find Edit Link menu item.")
        return nil
    }

    guard notesActive() else {
        stop("Notes lost focus.")
    }

    guard AXUIElementPerformAction(
        editItem, "AXPress" as CFString
    ) == .success else {
        key(53)
        pause(0.3)
        print("Could not activate Edit Link menu item.")
        return nil
    }

    var dialog: EditLinkDialog?
    for _ in 0..<12 {
        pause(0.25)
        guard notesActive() else {
            stop("Notes lost focus.")
        }
        if let found = findEditLinkDialog(
            notes: notes,
            editorWin: editorWin,
            expectedURL: link.url,
            expectedName: expectedCurrentName,
            allowEmptyName: allowEmptyName
        ) {
            dialog = found
            break
        }
    }

    guard let activeDialog = dialog else {
        print("Could not verify Edit Link dialog fields.")
        _ = findEditLinkDialog(
            notes: notes,
            editorWin: editorWin,
            expectedURL: link.url,
            expectedName: expectedCurrentName,
            allowEmptyName: allowEmptyName,
            trace: true
        )
        key(53)
        pause(0.3)
        return nil
    }

    guard setDialogFieldValue(
        activeDialog.nameField,
        dialog: activeDialog,
        notes: notes,
        expectedURL: link.url,
        to: newName
    ) else {
        print("Could not update Name field in Edit Link dialog.")
        dismissDialog(activeDialog)
        return nil
    }

    guard notesActive() else {
        stop("Notes lost focus.")
    }

    var confirmed = false
    if let ok = activeDialog.okButton,
       axBool(ok, "AXEnabled") != false,
       AXUIElementPerformAction(ok, "AXPress" as CFString) == .success {
        confirmed = true
    } else {
        key(36) // Return
        confirmed = true
    }

    guard confirmed else {
        dismissDialog(activeDialog)
        return nil
    }

    // Wait for the Edit Link sheet/popover to close.
    var dialogClosed = false
    for _ in 0..<12 {
        pause(0.25)
        guard notesActive() else {
            stop("Notes lost focus.")
        }
        let stillOpen = hasOpenEditLinkDialog(
            notes: notes,
            editorWin: editorWin,
            expectedURL: link.url
        )
        if !stillOpen {
            dialogClosed = true
            break
        }
    }

    guard dialogClosed else {
        print("Edit Link dialog did not close cleanly.")
        dismissDialog(activeDialog)
        return nil
    }

    // Verify exact occurrence-level text and URL invariants.
    for _ in 0..<12 {
        pause(0.3)
        guard notesActive() else {
            stop("Notes lost focus.")
        }

        guard let afterText = noteText(editor),
              let afterLinks = scan(editor)
        else { continue }

        guard afterLinks.map(\.url) == expectedLabels,
              afterLinks.count > targetIndex
        else { continue }

        let updated = afterLinks[targetIndex]
        if updated.url == link.url,
           updated.range.location == link.range.location,
           NSMaxRange(updated.range) <= afterText.length,
           afterText.substring(with: updated.range) == newName,
           (afterText as String) == expectedAfterText {
            return updated
        }
    }

    print("Could not verify link rename result at occurrence \(targetIndex).")
    return nil
}

guard AXIsProcessTrusted() else {
    stop("Enable Accessibility permission for Terminal first.")
}

if apply {
    print(normalizeMixed
        ? "APPLY MODE (mixed-script normalization enabled)"
        : "APPLY MODE (mixed-script normalization disabled)")
} else {
    print("DRY RUN — no note changes")
}
print("You have 5 seconds to click inside your note.")
pause(5)

guard notesActive() else {
    stop("Apple Notes is not active.")
}

guard let app = NSWorkspace.shared.frontmostApplication
else { stop("Cannot find Notes.") }

let notes = AXUIElementCreateApplication(app.processIdentifier)

func findEditor(_ raw: CFTypeRef?) -> AXUIElement? {
    guard let raw = raw,
          CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return nil }

    var element = raw as! AXUIElement

    for _ in 0..<15 {
        if attr(element, "AXRole") as? String == "AXTextArea" {
            return element
        }
        guard let parent = attr(element, "AXParent"),
              CFGetTypeID(parent) == AXUIElementGetTypeID()
        else { break }
        element = parent as! AXUIElement
    }
    return nil
}

var found = findEditor(attr(notes, "AXFocusedUIElement"))
    ?? findEditor(attr(system, "AXFocusedUIElement"))

if found == nil, let point = CGEvent(source: nil)?.location {
    var hit: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
        notes, Float(point.x), Float(point.y), &hit
    )
    print("Accessibility hit test: ", result.rawValue)
    if let hit = hit {
        found = findEditor(hit)
    }
}

guard let editor = found
else { stop("Cannot locate editor. Keep mouse over note text.") }

let editorWin = parentWindow(editor)

guard let original = scan(editor)
else { stop("Cannot read note contents through Accessibility.") }

let initialText = noteText(editor)

print("Detected \(original.count) candidate link(s).")
for link in original.reversed() {
    if let text = initialText,
       NSMaxRange(link.range) <= text.length {
        let label = text.substring(with: link.range)
        if needsLinkNormalization(label, link: link) {
            print("  \(link.url)  [mixed-script: \"\(label)\"]")
            continue
        }
    }
    print("  \(link.url)")
}

if !apply {
    print("Dry run complete. Run nlp to convert.")
    exit(0)
}

// V6: dynamic link positions + V11: mixed-script normalization & recovery
var converted = 0
var normalizedCount = 0
var skipped: [String] = []
var expectedLabels = original.map(\.url)

while true {
    guard notesActive() else {
        stop("Notes lost focus. Converted: \(converted)")
    }

    guard let links = scan(editor) else {
        stop("Cannot rescan note. Converted: \(converted)")
    }

    guard links.map(\.url) == expectedLabels else {
        stop("Unexpected link changes. Converted: \(converted)")
    }

    guard links.count > skipped.count else { break }

    let targetIndex = skipped.count
    let link = links[targetIndex]

    print("Processing: \(link.url)")

    guard let originalText = noteText(editor),
          NSMaxRange(link.range) <= originalText.length
    else { stop("Cannot verify target text range.") }

    let originalTargetText = originalText.substring(with: link.range)
    let inline = isInlineLink(originalText, link.range)

    print("Target text: \(originalTargetText)")
    print("Link type: \(inline ? "Inline" : "Standalone")")

    var activeLink = link
    var activeBeforeText = originalText
    var normalizedForConversion = false
    var normalizedDisplayName = ""

    if normalizeMixed && needsLinkNormalization(originalTargetText, link: link) {
        let tempName = asciiNormalizedURL(link.url)
        print("Mixed-script link detected — normalizing display text to URL before preview.")

        if let renamed = renameLinkTitle(
            editor: editor,
            notes: notes,
            editorWin: editorWin,
            link: link,
            targetIndex: targetIndex,
            expectedLabels: expectedLabels,
            beforeText: originalText,
            expectedCurrentName: originalTargetText,
            newName: tempName,
            allowEmptyName: false
        ), let postRenameText = noteText(editor) {
            activeLink = renamed
            activeBeforeText = postRenameText
            normalizedForConversion = true
            normalizedDisplayName = tempName
            print("Normalized display text to: \(tempName)")
        } else {
            if let currentText = noteText(editor),
               currentText.isEqual(originalText) {
                print("Skipped (could not normalize safely; note unchanged): \(link.url)")
                skipped.append(link.url)
                continue
            }
            stop("Edit Link left note in an unexpected state while normalizing \(link.url). Original title: \(originalTargetText). Check the note manually.")
        }
    }

    func attemptRestoreOriginalTitle() -> Bool {
        guard normalizedForConversion else { return true }
        guard let currentText = noteText(editor),
              currentText.isEqual(activeBeforeText),
              let currentLinks = scan(editor),
              currentLinks.map(\.url) == expectedLabels,
              currentLinks.count > targetIndex
        else { return false }

        let currentLink = currentLinks[targetIndex]
        guard renameLinkTitle(
            editor: editor,
            notes: notes,
            editorWin: editorWin,
            link: currentLink,
            targetIndex: targetIndex,
            expectedLabels: expectedLabels,
            beforeText: currentText,
            expectedCurrentName: normalizedDisplayName,
            newName: originalTargetText,
            allowEmptyName: true
        ) != nil else { return false }

        if let restoredText = noteText(editor) {
            return restoredText.isEqual(originalText)
        }
        return false
    }

    guard let item = openLinkContextMenu(
        editor: editor,
        notes: notes,
        link: activeLink,
        selectCompleteRange: inline,
        targetTitles: showPreviewMenuTitles
    ) else {
        if normalizedForConversion {
            if attemptRestoreOriginalTitle() {
                print("Restored original link title: \(originalTargetText)")
                print("Skipped: \(link.url)")
                skipped.append(link.url)
                continue
            }
            stop("Show Link Preview menu not found after normalization, and automatic title restore failed. Original title: \(originalTargetText), URL: \(link.url). Check the note manually.")
        }

        print("Skipped: \(link.url)")
        skipped.append(link.url)
        continue
    }

    guard notesActive() else {
        stop("Notes lost focus.")
    }

    guard AXUIElementPerformAction(
        item, "AXPress" as CFString
    ) == .success else {
        key(53)
        pause(0.3)
        if normalizedForConversion {
            let restored = attemptRestoreOriginalTitle()
            print(restored
                ? "Restored original link title: \(originalTargetText)"
                : "Automatic title restore did not complete.")
        }
        stop("Could not activate menu item.")
    }

    pause(1.2)

    var expectedAfter = expectedLabels
    expectedAfter.remove(at: targetIndex)

    var verified = false
    var lastCount = links.count

    // Wait for Notes to finish updating its document.
    for _ in 0..<16 {
        guard notesActive() else {
            stop("Notes lost focus.")
        }

        if let after = scan(editor) {
            lastCount = after.count

            if after.map(\.url) == expectedAfter {
                verified = true
                break
            }
        }

        pause(0.5)
    }

    guard verified else {
        print("Verification failed: \(link.url)")
        print("Original target: \(originalTargetText)")
        if normalizedForConversion {
            print("Normalized before preview: \(normalizedDisplayName)")
        }

        if let currentText = noteText(editor),
           let remaining = scan(editor) {

            let changedFromPrePreview = !currentText.isEqual(activeBeforeText)
            print("Document text changed:", changedFromPrePreview)

            for candidate in remaining where candidate.url == link.url {
                if NSMaxRange(candidate.range) <= currentText.length {
                    print("Remaining matching link:",
                          currentText.substring(with: candidate.range))
                }
            }

            if normalizedForConversion && !changedFromPrePreview {
                let restored = attemptRestoreOriginalTitle()
                print(restored
                    ? "Restored original link title: \(originalTargetText)"
                    : "Automatic title restore did not complete.")
            }
        }
        print("Links before: \(links.count)")
        print("Links after: \(lastCount)")
        print("Expected remaining: \(expectedAfter.count)")
        stop("Could not verify conversion. Check the note manually.")
    }

    expectedLabels = expectedAfter
    converted += 1
    if normalizedForConversion {
        normalizedCount += 1
    }
    print("Converted \(converted): \(link.url)")
}

print("")
print("========== SUMMARY ==========")
print("Detected: \(original.count)")
print("Converted: \(converted)")
print("Normalized (mixed-script): \(normalizedCount)")
print("Skipped: \(skipped.count)")

for name in skipped {
    print("  - \(name)")
}

print("=============================")
