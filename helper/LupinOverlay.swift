// Screen-centre title-card overlay for the lupin-title mod.
// Listens on 127.0.0.1:47391 for `POST /char` (typed text, one card per
// character with a clack) and `POST /title` (the whole prompt, full screen,
// with the sting), and `POST /think/{start,excuses,stop}` (a card counting
// the turn's time and typing out excuses for it). Exits after 30 idle
// minutes; the mod relaunches it. Each request may name the terminal app
// it came from (`?app=<bundle id>`): nothing is drawn or played while that
// app is not frontmost, and the thinking card waits hidden until it is.
import AppKit
import Network

let port: NWEndpoint.Port = 47391
let idleLimit: TimeInterval = 30 * 60
let soundDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : (CommandLine.arguments[0] as NSString).deletingLastPathComponent + "/../sounds")
let fontName = "HiraMinProN-W6"

func font(_ size: CGFloat) -> NSFont { NSFont(name: fontName, size: size) ?? .boldSystemFont(ofSize: size) }

final class Overlay {
    let booms = (0..<4).compactMap { NSSound(contentsOf: soundDir.appendingPathComponent("boom\($0).wav"), byReference: false) }
    let clacks = (0..<4).compactMap { NSSound(contentsOf: soundDir.appendingPathComponent("clack\($0).wav"), byReference: false) }
    let sting = NSSound(contentsOf: soundDir.appendingPathComponent("sting.wav"), byReference: false)
    var queue: [Character] = []
    var draining = false
    var cardHide: DispatchWorkItem?
    var titleHide: DispatchWorkItem?
    lazy var card = makeWindow(rounded: true)
    lazy var title = makeWindow(rounded: false)
    var lastActivity = Date()
    var titleShownAt = Date.distantPast
    lazy var think = makeThinkWindow()
    var thinkOwner: String?
    var thinkStart = Date()
    var excuses: [String] = []
    var excuseIndex = 0
    var thinkTimers: [Timer] = []
    var thinkShow: DispatchWorkItem?
    var typing: DispatchWorkItem?
    let groove = NSSound(contentsOf: soundDir.appendingPathComponent("groove.wav"), byReference: false)
    var music: NSSound?
    var musicFade: Timer?
    var thinkApp: String?
    var thinkAppeared = false
    var rotation: Timer?
    var lastNowAt = Date.distantPast
    var pendingNow: String?
    var pendingNowShow: DispatchWorkItem?
    let nowHold: TimeInterval = 2.5

    func makeThinkWindow() -> (NSWindow, NSTextField, NSTextField) {
        let (w, clock) = makeWindow(rounded: true)
        let excuse = NSTextField(labelWithString: "")
        excuse.textColor = NSColor(white: 0.85, alpha: 1)
        excuse.alignment = .center
        excuse.lineBreakMode = .byCharWrapping
        excuse.maximumNumberOfLines = 2
        excuse.translatesAutoresizingMaskIntoConstraints = false
        let bg = w.contentView!
        bg.addSubview(excuse)
        clock.removeFromSuperview()
        bg.addSubview(clock)
        NSLayoutConstraint.activate([
            clock.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            clock.topAnchor.constraint(equalTo: bg.topAnchor, constant: 36),
            excuse.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            excuse.topAnchor.constraint(equalTo: clock.bottomAnchor, constant: 24),
            excuse.widthAnchor.constraint(lessThanOrEqualTo: bg.widthAnchor, multiplier: 0.9),
        ])
        return (w, clock, excuse)
    }

    func makeWindow(rounded: Bool) -> (NSWindow, NSTextField) {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.hasShadow = false
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(rounded ? 0.88 : 0.94).cgColor
        bg.layer?.cornerRadius = rounded ? 28 : 0
        w.contentView = bg
        let label = NSTextField(labelWithString: "")
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byCharWrapping
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: bg.widthAnchor, multiplier: 0.88),
        ])
        return (w, label)
    }

    var screen: NSRect {
        let mouse = NSEvent.mouseLocation
        let s = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        return s.frame
    }

    func isFront(_ app: String?) -> Bool {
        guard let app, !app.isEmpty else { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app
    }

    /// The terminal came forward or went back: show or hide the thinking card with it.
    func frontmostChanged() {
        guard thinkOwner != nil, thinkAppeared else { return }
        let w = think.0
        if isFront(thinkApp) {
            w.alphaValue = 1
            w.orderFrontRegardless()
            music?.resume()
        } else {
            typing?.cancel()
            w.orderOut(nil)
            music?.pause()
        }
    }

    func play(_ s: NSSound?, volume: Float = 1) {
        guard let c = s?.copy() as? NSSound else { return }
        c.volume = volume
        c.play()
    }

    func type(_ text: String) {
        lastActivity = Date()
        queue.append(contentsOf: text)
        if !draining { drain() }
    }

    func drain() {
        guard !queue.isEmpty else { draining = false; return }
        draining = true
        let c = queue.removeFirst()
        play(clacks.randomElement())
        play(booms.randomElement())
        if !c.isWhitespace { showCard(String(c)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { self.drain() }
    }

    func showCard(_ s: String) {
        let (w, label) = card
        let side: CGFloat = 240
        let f = screen
        // A small jump per strike, so a repeated letter reads as separate keys.
        let dx = CGFloat.random(in: -14...14), dy = CGFloat.random(in: -10...10)
        w.setFrame(NSRect(x: f.midX - side / 2 + dx, y: f.midY - side / 2 + dy, width: side, height: side), display: false)
        label.font = font(170)
        cardHide?.cancel()
        let wasShown = w.isVisible && w.alphaValue > 0.5
        // Blank the card for a beat before the next letter lands.
        w.alphaValue = wasShown ? 0 : 1
        label.stringValue = s
        w.orderFrontRegardless()
        if wasShown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { w.alphaValue = 1 }
        }
        let hide = DispatchWorkItem { self.fade(w, 0.25) }
        cardHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: hide)
    }

    func showTitle(_ text: String) {
        lastActivity = Date()
        queue.removeAll()
        cardHide?.cancel()
        card.0.orderOut(nil)
        titleShownAt = Date()
        let (w, label) = title
        let f = screen
        w.setFrame(f, display: false)
        var size: CGFloat = 200
        let maxW = f.width * 0.88, maxH = f.height * 0.8
        while size > 24 {
            let r = (text as NSString).boundingRect(
                with: NSSize(width: maxW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: font(size)])
            if r.height <= maxH { break }
            size *= 0.9
        }
        label.font = font(size)
        label.preferredMaxLayoutWidth = maxW
        label.stringValue = text
        titleHide?.cancel()
        w.alphaValue = 1
        w.orderFrontRegardless()
        play(sting)
        let hide = DispatchWorkItem { self.fade(w, 0.5) }
        titleHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: hide)
    }

    func clockText(_ prefix: String) -> String {
        let t = Int(Date().timeIntervalSince(thinkStart))
        return String(format: "%@ %02d:%02d", prefix, t / 60, t % 60)
    }

    func thinkBegin(_ id: String, _ list: [String], app: String?) {
        lastActivity = Date()
        thinkEnd(final: false)
        thinkOwner = id
        thinkApp = app
        thinkStart = Date()
        excuses = list
        excuseIndex = 0
        // After the title card has faded (2.8 s + 0.5 s), give it one more second.
        let titleGone = titleShownAt.addingTimeInterval(3.3)
        let at = max(Date(), titleGone).addingTimeInterval(1.0)
        let show = DispatchWorkItem { self.thinkAppear() }
        thinkShow = show
        DispatchQueue.main.asyncAfter(deadline: .now() + at.timeIntervalSinceNow, execute: show)
    }

    func thinkAppear() {
        let (w, clock, excuse) = think
        let f = screen
        let width = min(f.width * 0.7, 1100), height: CGFloat = 300
        w.setFrame(NSRect(x: f.midX - width / 2, y: f.midY - height / 2, width: width, height: height), display: false)
        clock.font = font(84)
        clock.stringValue = clockText("思考時間")
        excuse.font = font(40)
        excuse.preferredMaxLayoutWidth = width * 0.9
        excuse.stringValue = ""
        thinkAppeared = true
        w.alphaValue = 1
        w.orderFrontRegardless()
        thinkTimers.append(Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            clock.stringValue = self.clockText("思考時間")
        })
        startMusic()
        if let now = pendingNow { pendingNow = nil; showNow(now) } else { nextExcuse() }
        restartRotation()
        frontmostChanged()
    }

    func restartRotation() {
        rotation?.invalidate()
        rotation = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { _ in self.nextExcuse() }
    }

    /// An excuse for what is running right now: shown at once, unless the last
    /// one has been up for less than `nowHold`, then as soon as it has.
    func excuseNow(_ line: String) {
        lastActivity = Date()
        guard think.0.isVisible, think.0.alphaValue > 0 else { pendingNow = line; return }
        let wait = lastNowAt.addingTimeInterval(nowHold).timeIntervalSinceNow
        pendingNow = line
        guard pendingNowShow == nil else { return }
        let show = DispatchWorkItem {
            self.pendingNowShow = nil
            if let next = self.pendingNow { self.pendingNow = nil; self.showNow(next) }
        }
        pendingNowShow = show
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, wait), execute: show)
    }

    func showNow(_ line: String) {
        lastNowAt = Date()
        typeOut(Array(line), into: think.2, shown: "")
        restartRotation()
    }

    func nextExcuse() {
        guard !excuses.isEmpty else { return }
        let line = excuses[excuseIndex % excuses.count]
        excuseIndex += 1
        typeOut(Array(line), into: think.2, shown: "")
    }

    func typeOut(_ rest: [Character], into label: NSTextField, shown: String) {
        typing?.cancel()
        label.stringValue = shown
        guard let c = rest.first else { return }
        let step = DispatchWorkItem {
            if !c.isWhitespace && label.window?.isVisible == true { self.play(self.clacks.randomElement(), volume: 0.6) }
            self.typeOut(Array(rest.dropFirst()), into: label, shown: shown + String(c))
        }
        typing = step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07, execute: step)
    }

    func startMusic() {
        stopMusic(fade: 0)
        guard let m = groove?.copy() as? NSSound else { return }
        m.loops = true
        m.volume = 0.55
        m.play()
        music = m
    }

    func stopMusic(fade: TimeInterval) {
        musicFade?.invalidate()
        guard let m = music else { return }
        music = nil
        guard fade > 0 else { m.stop(); return }
        let steps = 12.0, start = m.volume
        var i = 0.0
        musicFade = Timer.scheduledTimer(withTimeInterval: fade / steps, repeats: true) { t in
            i += 1
            m.volume = start * Float(max(0, 1 - i / steps))
            if i >= steps { m.stop(); t.invalidate() }
        }
    }

    func thinkEnd(final: Bool) {
        stopMusic(fade: final ? 0.8 : 0)
        thinkShow?.cancel()
        typing?.cancel()
        thinkTimers.forEach { $0.invalidate() }
        thinkTimers.removeAll()
        rotation?.invalidate()
        thinkAppeared = false
        pendingNowShow?.cancel()
        pendingNowShow = nil
        pendingNow = nil
        let (w, clock, excuse) = think
        guard final, w.isVisible, w.alphaValue > 0 else {
            if w.isVisible { w.orderOut(nil) }
            thinkOwner = nil
            return
        }
        clock.stringValue = clockText("所要時間")
        excuse.stringValue = "お待たせしました"
        play(clacks.randomElement())
        thinkOwner = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if self.thinkOwner == nil { self.fade(w, 0.5) }
        }
    }

    func fade(_ w: NSWindow, _ d: TimeInterval) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = d
            w.animator().alphaValue = 0
        }, completionHandler: { if w.alphaValue == 0 { w.orderOut(nil) } })
    }
}

let overlay = Overlay()

func respond(_ conn: NWConnection) {
    let body = "ok"
    let res = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    conn.send(content: res.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
}

func handle(_ conn: NWConnection, _ buffer: Data = Data()) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, err in
        var buf = buffer
        if let data { buf.append(data) }
        guard let sep = buf.range(of: Data("\r\n\r\n".utf8)) else {
            if done || err != nil || buf.count > 1_000_000 { conn.cancel() } else { handle(conn, buf) }
            return
        }
        let head = String(decoding: buf[..<sep.lowerBound], as: UTF8.self)
        let length = head.split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let bodyData = buf[sep.upperBound...]
        if bodyData.count < length && !done && err == nil { handle(conn, buf); return }
        let target = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let parts = target.split(separator: "?", maxSplits: 1).map(String.init)
        let path = parts.first ?? "/"
        let app = parts.count > 1
            ? parts[1].split(separator: "&").map(String.init)
                .first { $0.hasPrefix("app=") }
                .map { String($0.dropFirst(4)).removingPercentEncoding ?? "" }
            : nil
        let text = String(decoding: bodyData, as: UTF8.self)
        DispatchQueue.main.async {
            switch path {
            case "/char": if overlay.isFront(app) { overlay.type(text) }
            case "/title": if overlay.isFront(app) { overlay.showTitle(text) }
            case "/quit": DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
            case "/think/start", "/think/excuses", "/think/stop", "/think/now":
                let msg = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                let id = msg["id"] as? String ?? ""
                let list = (msg["excuses"] as? [String] ?? []).filter { !$0.isEmpty }
                if path == "/think/start" {
                    overlay.thinkBegin(id, list, app: app)
                } else if id == overlay.thinkOwner {
                    if path == "/think/stop" { overlay.thinkEnd(final: true) }
                    else if path == "/think/now", let line = msg["excuse"] as? String, !line.isEmpty { overlay.excuseNow(line) }
                    else if !list.isEmpty { overlay.excuses = list; overlay.excuseIndex = 0 }
                }
            default: break
            }
        }
        respond(conn)
    }
}

let params = NWParameters.tcp
params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
let listener: NWListener
do { listener = try NWListener(using: params) } catch { exit(1) }
listener.newConnectionHandler = { conn in
    conn.start(queue: .main)
    handle(conn)
}
listener.stateUpdateHandler = { state in
    if case .failed = state { exit(1) }  // port taken: another session's helper already serves
}
listener.start(queue: .main)

Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
    if Date().timeIntervalSince(overlay.lastActivity) > idleLimit { exit(0) }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { _ in overlay.frontmostChanged() }

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
