// 목록형 자막 창 8판.
//   - 제목 막대를 두 번 누르면 같은 모양 그대로 작게 줄고, 다시 두 번 누르면 커진다.
//     작아도 자막은 계속 흐르므로 최근 몇 줄은 그대로 보인다.
//   - 바탕을 흐리지 않고 그대로 비추되, 글자에 그림자를 넣어 읽히게 한다.
//   - 사방 여덟 곳에서 크기를 바꾸고, 자리·크기·글자 크기·투명도를 기억한다.
//
// 표준입력 형식
//   >3 원문 / =3 번역   (같은 번호가 다시 오면 그 자리를 고친다)
import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let DEF = UserDefaults.standard
let BAR: CGFloat = 30
let EDGE: CGFloat = 7
let SMALL = NSSize(width: 380, height: 150)
let GROUP_GAP = Double(ProcessInfo.processInfo.environment["SUBTITLE_GAP"] ?? "") ?? 45

let screen = NSScreen.main!.visibleFrame
var rect = NSRect(x: screen.maxX - 620, y: screen.minY + 60, width: 580, height: 480)
if let saved = DEF.string(forKey: "frame") {
    let r = NSRectFromString(saved)
    if r.width > 240, r.height > 140, screen.intersects(r) { rect = r }
}

var fontSize = CGFloat(DEF.double(forKey: "fontSize") == 0 ? 18 : DEF.double(forKey: "fontSize"))
// 바탕이 얼마나 짙은지. 0 에 가까울수록 뒤가 잘 보인다.
let DIM_DEFAULT: CGFloat = 0.52
var dim = CGFloat(DEF.object(forKey: "dim") == nil ? Double(DIM_DEFAULT) : DEF.double(forKey: "dim"))
if abs(dim - 0.42) < 0.001 { dim = DIM_DEFAULT }   // 예전 기본값이면 새 기본값으로
var onTop = DEF.object(forKey: "onTop") as? Bool ?? true

let win = NSWindow(contentRect: rect, styleMask: [.borderless, .resizable],
                   backing: .buffered, defer: false)
win.isOpaque = false
win.backgroundColor = .clear
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
win.minSize = NSSize(width: 300, height: 160)
win.appearance = NSAppearance(named: .vibrantDark)
win.level = onTop ? .floating : .normal

// 흐림 효과를 쓰지 않는다. 뒤를 그대로 비춰야 회의 화면이 보인다.
let root = NSView(frame: NSRect(origin: .zero, size: rect.size))
root.wantsLayer = true
root.layer?.cornerRadius = 12
root.layer?.masksToBounds = true
root.layer?.borderWidth = 1
root.autoresizingMask = [.width, .height]
win.contentView = root

func applyDim() {
    root.layer?.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
    root.layer?.borderColor = NSColor.white.withAlphaComponent(0.06 + dim * 0.18).cgColor
}
applyDim()

// MARK: - 제목 막대

final class DragBar: NSView {
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with e: NSEvent) {
        // 두 번 누르면 크기를 오간다. performDrag 는 그 자리에서 잡아 두므로 먼저 걸러야 한다.
        if e.clickCount == 2 { onDoubleClick?(); return }
        window?.performDrag(with: e)
    }
    override func mouseDragged(with e: NSEvent) { window?.performDrag(with: e) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

let bar = DragBar(frame: NSRect(x: 0, y: rect.height - BAR, width: rect.width, height: BAR))
bar.autoresizingMask = [.width, .minYMargin]
root.addSubview(bar)

let sep = NSView(frame: NSRect(x: 0, y: 0, width: rect.width, height: 1))
sep.autoresizingMask = [.width]
sep.wantsLayer = true
sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
bar.addSubview(sep)

func label(_ s: String, _ x: CGFloat, _ w: CGFloat, _ size: CGFloat,
           _ alpha: CGFloat, _ align: NSTextAlignment) -> NSTextField {
    let f = NSTextField(labelWithString: s)
    f.frame = NSRect(x: x, y: 8, width: w, height: 15)
    f.font = .systemFont(ofSize: size, weight: .medium)
    f.textColor = NSColor.white.withAlphaComponent(alpha)
    f.alignment = align
    f.shadow = {
        let sh = NSShadow(); sh.shadowColor = .black
        sh.shadowBlurRadius = 3; sh.shadowOffset = NSSize(width: 0, height: -1); return sh
    }()
    return f
}

let titleLabel = label("실시간 자막", 14, 200, 11.5, 0.6, .left)
bar.addSubview(titleLabel)
let hint = label("두 번 눌러 크게·작게", rect.width - 230, 120, 10.5, 0.34, .right)
hint.autoresizingMask = [.minXMargin]
bar.addSubview(hint)

// 단축키를 외우지 않아도 되게, 하는 일은 모두 단추로도 닿을 수 있게 한다.
func barButton(_ title: String, _ x: CGFloat, _ size: CGFloat, _ tip: String) -> NSButton {
    let b = NSButton(title: title, target: nil, action: nil)
    b.frame = NSRect(x: rect.width - x, y: 4, width: 24, height: 22)
    b.isBordered = false
    b.font = .systemFont(ofSize: size, weight: .bold)
    b.contentTintColor = NSColor.white.withAlphaComponent(0.6)
    b.autoresizingMask = [.minXMargin]
    b.toolTip = tip
    bar.addSubview(b)
    return b
}

let menuBtn = barButton("⋯", 88, 15, "글자 크기, 투명도, 맨 위 고정")
let hideBtn = barButton("―", 60, 14, "작게 (제목 막대를 두 번 눌러도 됩니다)")
let closeBtn = barButton("✕", 32, 12, "자막 끝내기")

// MARK: - 본문

let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: rect.width, height: rect.height - BAR))
scroll.hasVerticalScroller = true
scroll.drawsBackground = false
scroll.scrollerKnobStyle = .light
scroll.autoresizingMask = [.width, .height]

let text = NSTextView(frame: scroll.bounds)
text.isEditable = false
text.drawsBackground = false
text.textContainerInset = NSSize(width: 20, height: 16)
text.autoresizingMask = [.width]
text.isVerticallyResizable = true
text.textContainer?.widthTracksTextView = true
scroll.documentView = text
root.addSubview(scroll)

// MARK: - 사방 크기 조절

final class ResizeEdge: NSView {
    let ox: CGFloat, oy: CGFloat, ow: CGFloat, oh: CGFloat
    let cursor: NSCursor
    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero
    init(_ frame: NSRect, _ ox: CGFloat, _ oy: CGFloat, _ ow: CGFloat, _ oh: CGFloat,
         _ mask: NSView.AutoresizingMask, _ cursor: NSCursor) {
        self.ox = ox; self.oy = oy; self.ow = ow; self.oh = oh; self.cursor = cursor
        super.init(frame: frame); autoresizingMask = mask
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    override func mouseDown(with e: NSEvent) {
        startMouse = NSEvent.mouseLocation; startFrame = window?.frame ?? .zero
    }
    override func mouseDragged(with e: NSEvent) {
        guard let w = window else { return }
        let now = NSEvent.mouseLocation
        let mdx = now.x - startMouse.x, mdy = now.y - startMouse.y
        let width  = max(w.minSize.width,  startFrame.width  + ow * mdx)
        let height = max(w.minSize.height, startFrame.height + oh * mdy)
        let x = ox != 0 ? startFrame.maxX - width  : startFrame.minX
        let y = oy != 0 ? startFrame.maxY - height : startFrame.minY
        w.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

let W0 = rect.width, H0 = rect.height, C: CGFloat = 14
let edges: [ResizeEdge] = [
    ResizeEdge(NSRect(x: 0, y: C, width: EDGE, height: H0 - 2*C), 1, 0, -1, 0, [.height, .maxXMargin], .resizeLeftRight),
    ResizeEdge(NSRect(x: W0-EDGE, y: C, width: EDGE, height: H0 - 2*C), 0, 0, 1, 0, [.height, .minXMargin], .resizeLeftRight),
    ResizeEdge(NSRect(x: C, y: 0, width: W0 - 2*C, height: EDGE), 0, 1, 0, -1, [.width, .maxYMargin], .resizeUpDown),
    ResizeEdge(NSRect(x: C, y: H0-EDGE, width: W0 - 2*C, height: EDGE), 0, 0, 0, 1, [.width, .minYMargin], .resizeUpDown),
    ResizeEdge(NSRect(x: 0, y: 0, width: C, height: C), 1, 1, -1, -1, [.maxXMargin, .maxYMargin], .crosshair),
    ResizeEdge(NSRect(x: W0-C, y: 0, width: C, height: C), 0, 1, 1, -1, [.minXMargin, .maxYMargin], .crosshair),
    ResizeEdge(NSRect(x: 0, y: H0-C, width: C, height: C), 1, 0, -1, 1, [.maxXMargin, .minYMargin], .crosshair),
    ResizeEdge(NSRect(x: W0-C, y: H0-C, width: C, height: C), 0, 0, 1, 1, [.minXMargin, .minYMargin], .crosshair),
]
for e in edges { root.addSubview(e) }

final class GripMark: NSView {
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ dirty: NSRect) {
        NSColor.white.withAlphaComponent(0.32).setStroke()
        for i in 0..<3 {
            let o = CGFloat(i) * 4 + 4
            let p = NSBezierPath()
            p.move(to: NSPoint(x: bounds.maxX - o, y: bounds.minY + 3))
            p.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + o))
            p.lineWidth = 1.1; p.stroke()
        }
    }
}
let mark = GripMark(frame: NSRect(x: W0-C, y: 0, width: C, height: C))
mark.autoresizingMask = [.minXMargin, .maxYMargin]
root.addSubview(mark)

// MARK: - 크게 / 작게

var small = DEF.bool(forKey: "small")
var bigFrame = rect
var smallFrame = NSRect(x: rect.maxX - SMALL.width, y: rect.maxY - SMALL.height,
                        width: SMALL.width, height: SMALL.height)
if let v = DEF.string(forKey: "bigFrame") { let r = NSRectFromString(v); if r.width > 240 { bigFrame = r } }
if let v = DEF.string(forKey: "smallFrame") { let r = NSRectFromString(v); if r.width > 240 { smallFrame = r } }

func setSmall(_ v: Bool) {
    // 모양은 그대로 두고 크기만 오간다. 오른쪽 위 모서리를 붙잡아 두어
    // 줄었다 커져도 창이 엉뚱한 곳으로 튀지 않는다.
    if small != v {
        if small { smallFrame = win.frame } else { bigFrame = win.frame }
    }
    small = v
    let target = v ? smallFrame : bigFrame
    let anchored = NSRect(x: (v ? bigFrame : smallFrame).maxX - target.width,
                          y: (v ? bigFrame : smallFrame).maxY - target.height,
                          width: target.width, height: target.height)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.16
        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        win.animator().setFrame(anchored, display: true)
    }
    if v { smallFrame = anchored } else { bigFrame = anchored }
    hideBtn.title = v ? "▢" : "―"
    hideBtn.toolTip = v ? "크게 (제목 막대를 두 번 눌러도 됩니다)" : "작게 (제목 막대를 두 번 눌러도 됩니다)"
    DEF.set(small, forKey: "small")
}

// MARK: - 그리기

var sources: [Int: String] = [:]
var targets: [Int: String] = [:]
var stamps:  [Int: Date] = [:]
var order: [Int] = []

let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

func para(_ before: CGFloat, _ after: CGFloat, _ gap: CGFloat) -> NSMutableParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.paragraphSpacingBefore = before; p.paragraphSpacing = after; p.lineSpacing = gap
    return p
}

// 바탕을 비추는 만큼 글자는 그림자로 띄운다. 밝은 화면 위에서도 읽힌다.
let glow: NSShadow = {
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(0.95)
    sh.shadowBlurRadius = 4
    sh.shadowOffset = NSSize(width: 0, height: -1)
    return sh
}()

func redraw() {
    let clip = scroll.contentView
    let atBottom = clip.bounds.origin.y + clip.bounds.height >= (text.frame.height - 28)

    let out = NSMutableAttributedString()
    var last: Date? = nil
    for id in order {
        let when = stamps[id] ?? Date()
        let newGroup = last == nil || when.timeIntervalSince(last!) > GROUP_GAP
        if newGroup {
            out.append(NSAttributedString(string: clock.string(from: when) + "\n", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                .paragraphStyle: para(out.length == 0 ? 0 : 20, 7, 0),
                .shadow: glow,
            ]))
        }
        last = when

        if let s = sources[id], !s.isEmpty {
            out.append(NSAttributedString(string: s + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize * 0.86, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.72),
                .paragraphStyle: para(newGroup ? 0 : 13, 1, 3),
                .shadow: glow,
            ]))
        }
        let pending = targets[id] == nil
        out.append(NSAttributedString(string: (targets[id] ?? "…") + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(pending ? 0.38 : 0.98),
            .paragraphStyle: para(sources[id] == nil && !newGroup ? 13 : 1, 0, 4),
            .shadow: glow,
        ]))
    }
    text.textStorage?.setAttributedString(out)
    if atBottom { text.scrollToEndOfDocument(nil) }
}

func save() {
    if small { smallFrame = win.frame } else { bigFrame = win.frame }
    DEF.set(NSStringFromRect(bigFrame), forKey: "bigFrame")
    DEF.set(NSStringFromRect(smallFrame), forKey: "smallFrame")
    DEF.set(NSStringFromRect(win.frame), forKey: "frame")
    DEF.set(Double(fontSize), forKey: "fontSize")
    DEF.set(Double(dim), forKey: "dim")
    DEF.set(onTop, forKey: "onTop")
}

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
    if e.keyCode == 53 { save(); app.terminate(nil) }
    if e.modifierFlags.contains(.command) {
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "=", "+": fontSize = min(fontSize + 2, 44); redraw(); save(); return nil
        case "-":      fontSize = max(fontSize - 2, 11); redraw(); save(); return nil
        case "[":      dim = max(dim - 0.08, 0.05); applyDim(); save(); return nil
        case "]":      dim = min(dim + 0.08, 0.92); applyDim(); save(); return nil
        case "h":      setSmall(!small); return nil
        case "t":      bridge.toggleTop(); return nil
        default: break
        }
    }
    return e
}
hideBtn.target = nil
hideBtn.action = nil

let topItem = NSMenuItem(title: "항상 맨 위에 두기", action: nil, keyEquivalent: "")

final class Bridge: NSObject {
    @objc func toggleMin() { setSmall(!small) }
    @objc func quitNow() { save(); app.terminate(nil) }
    @objc func fontUp()   { fontSize = min(fontSize + 2, 44); redraw(); save() }
    @objc func fontDown() { fontSize = max(fontSize - 2, 11); redraw(); save() }
    @objc func dimUp()    { dim = min(dim + 0.07, 0.92); applyDim(); save() }
    @objc func dimDown()  { dim = max(dim - 0.07, 0.05); applyDim(); save() }
    @objc func toggleTop() {
        onTop.toggle()
        win.level = onTop ? .floating : .normal
        topItem.state = onTop ? .on : .off
        titleLabel.stringValue = onTop ? "실시간 자막" : "실시간 자막  (맨 위 해제)"
        save()
    }
    @objc func popMenu(_ sender: NSButton) {
        settings.popUp(positioning: nil,
                       at: NSPoint(x: sender.bounds.minX - 150, y: sender.bounds.minY - 6),
                       in: sender)
    }
}
let bridge = Bridge()

let settings = NSMenu()
settings.addItem(withTitle: "글자 크게", action: #selector(Bridge.fontUp), keyEquivalent: "")
settings.addItem(withTitle: "글자 작게", action: #selector(Bridge.fontDown), keyEquivalent: "")
settings.addItem(.separator())
settings.addItem(withTitle: "더 진하게", action: #selector(Bridge.dimUp), keyEquivalent: "")
settings.addItem(withTitle: "더 투명하게", action: #selector(Bridge.dimDown), keyEquivalent: "")
settings.addItem(.separator())
topItem.action = #selector(Bridge.toggleTop)
topItem.state = onTop ? .on : .off
settings.addItem(topItem)
settings.addItem(.separator())
settings.addItem(withTitle: "크게 / 작게", action: #selector(Bridge.toggleMin), keyEquivalent: "")
settings.addItem(withTitle: "자막 끝내기", action: #selector(Bridge.quitNow), keyEquivalent: "")
for i in settings.items { i.target = bridge }

menuBtn.target = bridge;  menuBtn.action = #selector(Bridge.popMenu)
hideBtn.target = bridge;  hideBtn.action = #selector(Bridge.toggleMin)
closeBtn.target = bridge; closeBtn.action = #selector(Bridge.quitNow)

// 본문 어디서나 오른쪽 클릭으로도 같은 메뉴가 열린다
text.menu = settings
bar.menu = settings

// 메뉴 막대에도 남겨 둔다. 창을 화면 밖으로 밀어 두었을 때의 통로다.
let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
status.button?.title = "자막"
status.button?.font = .systemFont(ofSize: 12, weight: .medium)
status.menu = settings

let center = NotificationCenter.default
center.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main) { _ in save() }
center.addObserver(forName: NSWindow.didResizeNotification, object: win, queue: .main) { _ in save() }

bar.onDoubleClick = { setSmall(!small) }
if small { setSmall(true) }

win.orderFrontRegardless()
FileHandle.standardError.write("WINDOWID=\(win.windowNumber)\n".data(using: .utf8)!)

DispatchQueue.global().async {
    while let line = readLine(strippingNewline: true) {
        guard let kind = line.first else { continue }
        let rest = line.dropFirst()
        guard let sp = rest.firstIndex(of: " "),
              let id = Int(rest[rest.startIndex..<sp]) else { continue }
        let body = String(rest[rest.index(after: sp)...])
        DispatchQueue.main.async {
            if !order.contains(id) { order.append(id); stamps[id] = Date() }
            if kind == ">" { sources[id] = body } else if kind == "=" { targets[id] = body }
            redraw()
        }
    }
    DispatchQueue.main.async { save(); app.terminate(nil) }
}

app.run()
