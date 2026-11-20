import AppKit

@MainActor
final class PetView: NSView {
    private enum State {
        case idle
        case reminding
        case miniList
        case panelOpen
        case held
        case dropping
        case sleeping
        case waking
    }

    private enum WalkDirection {
        case side
        case up
        case down
    }

    private enum IdleMood {
        case normal
        case happy
    }

    var onReminderRequested: (() -> Void)?
    var onListRequested: ((NSRect) -> Bool)?
    var onPickUp: (() -> Void)?
    var onDrop: (() -> Void)?
    var onResumeWalking: (() -> Void)?
    var onSleepRequested: (() -> Void)?
    var onWakeRequested: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?

    private let spriteSheet: NSImage
    private let walkSheet: NSImage
    private let walkUpSheet: NSImage
    private let walkDownSheet: NSImage
    private let landingSheet: NSImage
    private let happySheet: NSImage
    private let sleepSheet: NSImage
    private let wakeSheet: NSImage
    private var state: State = .idle
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var bobPhase: CGFloat = 0
    private var bobTimer: Timer?
    private var pickupTimer: Timer?
    private var dropTimer: Timer?
    private var miniListTimer: Timer?
    private var sleepTimer: Timer?
    private var wakeTimer: Timer?
    private var previousScreenLocation: NSPoint?
    private var didDrag = false
    private var isWalking = false
    private var facingRight = true
    private var walkDirection: WalkDirection = .side
    private var idleMood: IdleMood = .normal
    private var swingAngle: CGFloat = 0
    private var dropProgress: CGFloat = 0
    private var wakeProgress: CGFloat = 0
    private var remindAfterDrop = false
    private var expandAfterReminder = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        let packagedURL = Bundle.main.url(forResource: "moss-reminder", withExtension: "png")
        let developmentURL = Bundle.module.url(forResource: "moss-reminder", withExtension: "png")
        let packagedWalkURL = Bundle.main.url(forResource: "moss-walk", withExtension: "png")
        let developmentWalkURL = Bundle.module.url(forResource: "moss-walk", withExtension: "png")
        let packagedWalkUpURL = Bundle.main.url(forResource: "moss-walk-up", withExtension: "png")
        let developmentWalkUpURL = Bundle.module.url(forResource: "moss-walk-up", withExtension: "png")
        let packagedWalkDownURL = Bundle.main.url(forResource: "moss-walk-down", withExtension: "png")
        let developmentWalkDownURL = Bundle.module.url(forResource: "moss-walk-down", withExtension: "png")
        let packagedLandingURL = Bundle.main.url(forResource: "moss-land", withExtension: "png")
        let developmentLandingURL = Bundle.module.url(forResource: "moss-land", withExtension: "png")
        let packagedHappyURL = Bundle.main.url(forResource: "moss-happy", withExtension: "png")
        let developmentHappyURL = Bundle.module.url(forResource: "moss-happy", withExtension: "png")
        let packagedSleepURL = Bundle.main.url(forResource: "moss-sleep", withExtension: "png")
        let developmentSleepURL = Bundle.module.url(forResource: "moss-sleep", withExtension: "png")
        let packagedWakeURL = Bundle.main.url(forResource: "moss-wake", withExtension: "png")
        let developmentWakeURL = Bundle.module.url(forResource: "moss-wake", withExtension: "png")
        guard
            let url = packagedURL ?? developmentURL,
            let image = NSImage(contentsOf: url),
            let walkURL = packagedWalkURL ?? developmentWalkURL,
            let walkImage = NSImage(contentsOf: walkURL),
            let walkUpURL = packagedWalkUpURL ?? developmentWalkUpURL,
            let walkUpImage = NSImage(contentsOf: walkUpURL),
            let walkDownURL = packagedWalkDownURL ?? developmentWalkDownURL,
            let walkDownImage = NSImage(contentsOf: walkDownURL),
            let landingURL = packagedLandingURL ?? developmentLandingURL,
            let landingImage = NSImage(contentsOf: landingURL),
            let happyURL = packagedHappyURL ?? developmentHappyURL,
            let happyImage = NSImage(contentsOf: happyURL),
            let sleepURL = packagedSleepURL ?? developmentSleepURL,
            let sleepImage = NSImage(contentsOf: sleepURL),
            let wakeURL = packagedWakeURL ?? developmentWakeURL,
            let wakeImage = NSImage(contentsOf: wakeURL)
        else {
            fatalError("Missing a Moss sprite resource")
        }

        spriteSheet = image
        walkSheet = walkImage
        walkUpSheet = walkUpImage
        walkDownSheet = walkDownImage
        landingSheet = landingImage
        happySheet = happyImage
        sleepSheet = sleepImage
        wakeSheet = wakeImage
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        startIdleBob()
        resetSleepCountdown()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSGraphicsContext.current?.imageInterpolation = .none
        let lift = state == .idle ? abs(sin(bobPhase)) * (isWalking ? 3 : 1.2) : 0
        let fullDestination = NSRect(x: 2, y: 2 + lift, width: bounds.width - 4, height: bounds.height - 4)
        var destination = fullDestination.insetBy(dx: 6, dy: 6)

        if state == .held {
            drawPickedUp(in: destination)
            return
        }
        if state == .dropping {
            drawLanding(in: destination)
            return
        }
        if state == .miniList {
            drawMiniListScene(characterIn: destination, sceneIn: fullDestination)
            return
        }
        if state == .sleeping || state == .waking {
            drawSleepLifecycle(in: destination)
            return
        }

        if state == .idle, !isWalking, idleMood != .normal {
            drawIdleMood(in: destination)
            return
        }

        let drawingWalkCycle = isWalking && state == .idle
        if drawingWalkCycle {
            let container = destination.insetBy(dx: -12, dy: -12)
            let activeWalkSheet = currentWalkSheet
            destination = aspectFitRect(for: stripFrameSize(in: activeWalkSheet), inside: container)
        }

        let context = NSGraphicsContext.current
        context?.saveGraphicsState()
        if !facingRight, walkDirection == .side, state == .idle {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
        }
        let activeWalkSheet = currentWalkSheet
        let image = drawingWalkCycle ? activeWalkSheet : spriteSheet
        let source = drawingWalkCycle ? walkSourceRect(in: activeWalkSheet) : sourceRect(for: frameIndex)
        image.draw(
            in: destination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        context?.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        resetSleepCountdown()
        previousScreenLocation = NSEvent.mouseLocation
        didDrag = false

        if state == .sleeping || state == .waking {
            // The first half of a double-click begins the normal wake-up.
            // Catch its second mouse-down while Moss is still waking and go
            // straight to the full quest log, without conjuring the mini list.
            if event.clickCount >= 2 {
                openTaskPanelFromSleep()
            }
            return
        }
        guard state != .reminding, state != .dropping else { return }
        if state == .miniList {
            openTaskPanel()
            return
        }

        pickupTimer?.invalidate()
        pickupTimer = Timer.scheduledTimer(
            timeInterval: 0.12,
            target: self,
            selector: #selector(beginPickupFromTimer(_:)),
            userInfo: nil,
            repeats: false
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previous = previousScreenLocation else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - previous.x, y: current.y - previous.y)
        previousScreenLocation = current

        if !didDrag {
            let distance = hypot(delta.x, delta.y)
            didDrag = distance > 2
        }
        guard didDrag else { return }

        pickupTimer?.invalidate()
        pickupTimer = nil
        if state != .held {
            beginPickup()
        }
        swingAngle = min(max(-delta.x * 0.025, -0.24), 0.24)
        onDrag?(delta)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pickupTimer?.invalidate()
        pickupTimer = nil

        defer {
            previousScreenLocation = nil
            didDrag = false
        }

        if state == .held {
            remindAfterDrop = !didDrag
            beginDrop()
            return
        }

        guard !didDrag else { return }

        switch state {
        case .idle:
            playReminder()
        case .sleeping:
            beginWakeUp()
        case .reminding:
            // Treat a second click during the conjuring animation as the
            // user's request to expand the list as soon as it appears.
            expandAfterReminder = true
        case .miniList:
            openTaskPanel()
        case .panelOpen, .held, .dropping, .waking:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show reminder", action: #selector(showReminderFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Moss", action: #selector(quitMoss), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    func returnToIdle() {
        animationTimer?.invalidate()
        animationTimer = nil
        dropTimer?.invalidate()
        dropTimer = nil
        miniListTimer?.invalidate()
        miniListTimer = nil
        wakeTimer?.invalidate()
        wakeTimer = nil
        state = .idle
        frameIndex = 0
        idleMood = .normal
        resetSleepCountdown()
        needsDisplay = true
    }

    func setWalking(_ walking: Bool, horizontal: CGFloat, vertical: CGFloat) {
        guard state == .idle else { return }
        let wasWalking = isWalking
        isWalking = walking
        if walking {
            idleMood = .normal
            facingRight = horizontal >= 0
            if abs(vertical) > abs(horizontal) * 0.72 {
                walkDirection = vertical > 0 ? .up : .down
            } else {
                walkDirection = .side
            }
        } else if wasWalking {
            let roll = Int.random(in: 0..<100)
            idleMood = roll < 42 ? .happy : .normal
        }
        needsDisplay = true
    }

    @objc private func showReminderFromMenu() {
        resetSleepCountdown()
        playReminder()
    }

    @objc private func quitMoss() {
        NSApplication.shared.terminate(nil)
    }

    private func playReminder() {
        resetSleepCountdown()
        pickupTimer?.invalidate()
        dropTimer?.invalidate()
        miniListTimer?.invalidate()
        animationTimer?.invalidate()
        onReminderRequested?()
        isWalking = false
        idleMood = .normal
        expandAfterReminder = false
        state = .reminding
        frameIndex = 0
        needsDisplay = true

        animationTimer = Timer.scheduledTimer(
            timeInterval: 0.22,
            target: self,
            selector: #selector(advanceReminderFrame(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func advanceReminderFrame(_ timer: Timer) {
        if frameIndex < 7 {
            frameIndex += 1
            needsDisplay = true
        } else {
            timer.invalidate()
            animationTimer = nil
            state = .miniList
            needsDisplay = true

            if expandAfterReminder {
                expandAfterReminder = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self, self.state == .miniList else { return }
                    self.openTaskPanel()
                }
            } else {
                miniListTimer = Timer.scheduledTimer(
                    timeInterval: 2.7,
                    target: self,
                    selector: #selector(dismissMiniList(_:)),
                    userInfo: nil,
                    repeats: false
                )
            }
        }
    }

    @objc private func dismissMiniList(_ timer: Timer) {
        guard state == .miniList else { return }
        miniListTimer = nil
        state = .idle
        frameIndex = 0
        needsDisplay = true
        onResumeWalking?()
    }

    private func openTaskPanel() {
        guard state == .miniList else { return }
        miniListTimer?.invalidate()
        miniListTimer = nil
        let anchor = miniListAnchorRect
        let didOpenPanel = onListRequested?(anchor) ?? false

        frameIndex = 0
        idleMood = .normal
        needsDisplay = true

        if didOpenPanel {
            // The panel owns the one visible Moss while it is open.
            state = .panelOpen
        } else {
            state = .idle
            onResumeWalking?()
            resetSleepCountdown()
        }
    }

    private func openTaskPanelFromSleep() {
        guard state == .sleeping || state == .waking else { return }

        sleepTimer?.invalidate()
        sleepTimer = nil
        wakeTimer?.invalidate()
        wakeTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
        miniListTimer?.invalidate()
        miniListTimer = nil

        isWalking = false
        frameIndex = 0
        idleMood = .normal
        let didOpenPanel = onListRequested?(miniListAnchorRect) ?? false

        if didOpenPanel {
            state = .panelOpen
        } else {
            state = .idle
            onResumeWalking?()
            resetSleepCountdown()
        }
        needsDisplay = true
    }

    private func startIdleBob() {
        bobTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      self.state == .idle || self.state == .held || self.state == .dropping
                        || self.state == .miniList || self.state == .sleeping || self.state == .waking
                else { return }
                self.bobPhase += 0.12
                if self.state == .held {
                    self.swingAngle *= 0.88
                }
                self.needsDisplay = true
            }
        }
    }

    @objc private func beginPickupFromTimer(_ timer: Timer) {
        pickupTimer = nil
        beginPickup()
    }

    private func beginPickup() {
        guard state == .idle || state == .miniList else { return }
        animationTimer?.invalidate()
        animationTimer = nil
        miniListTimer?.invalidate()
        miniListTimer = nil
        state = .held
        frameIndex = 0
        dropProgress = 0
        swingAngle = 0
        isWalking = false
        idleMood = .normal
        onPickUp?()
        needsDisplay = true
    }

    private func resetSleepCountdown() {
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(
            timeInterval: Double.random(in: 12...20),
            target: self,
            selector: #selector(beginSleepingIfPossible(_:)),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func beginSleepingIfPossible(_ timer: Timer) {
        sleepTimer = nil
        guard state == .idle else {
            resetSleepCountdown()
            return
        }
        state = .sleeping
        isWalking = false
        idleMood = .normal
        onSleepRequested?()
        needsDisplay = true
    }

    private func beginWakeUp() {
        guard state == .sleeping else { return }
        state = .waking
        wakeProgress = 0
        wakeTimer?.invalidate()
        wakeTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(advanceWakeUp(_:)),
            userInfo: nil,
            repeats: true
        )
        needsDisplay = true
    }

    @objc private func advanceWakeUp(_ timer: Timer) {
        wakeProgress += 1.0 / 48.0
        if wakeProgress >= 1 {
            timer.invalidate()
            wakeTimer = nil
            state = .idle
            frameIndex = 0
            idleMood = .normal
            onWakeRequested?()
        }
        needsDisplay = true
    }

    private func beginDrop() {
        state = .dropping
        dropProgress = 0
        dropTimer?.invalidate()
        dropTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(advanceDrop(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func advanceDrop(_ timer: Timer) {
        dropProgress += 1.0 / 28.0
        if dropProgress >= 1 {
            timer.invalidate()
            dropTimer = nil
            state = .idle
            frameIndex = 0
            swingAngle = 0
            let shouldRemind = remindAfterDrop
            remindAfterDrop = false
            onDrop?()
            if shouldRemind {
                playReminder()
            }
        }
        needsDisplay = true
    }

    private func drawPickedUp(in baseDestination: NSRect) {
        guard let context = NSGraphicsContext.current else { return }

        let source = stripSourceRect(frame: 0, in: landingSheet)
        let container = baseDestination.insetBy(dx: -12, dy: -12)
        var destination = aspectFitRect(for: source.size, inside: container)
        destination.origin.y -= 3
        let pivot = NSPoint(x: destination.midX, y: destination.maxY - 3)

        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: pivot.x, yBy: pivot.y)
        transform.rotate(byRadians: swingAngle)
        transform.translateX(by: -pivot.x, yBy: -pivot.y)
        transform.concat()

        landingSheet.draw(
            in: destination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        context.restoreGraphicsState()
    }

    private func drawLanding(in destination: NSRect) {
        let frame = min(3, Int(dropProgress * 4))
        let source = stripSourceRect(frame: frame, in: landingSheet)
        let fallPhase = min(dropProgress / 0.56, 1)
        var container = destination.insetBy(dx: -12, dy: -12)
        container.origin.y += 8 - (fallPhase * 18)
        let fittedDestination = aspectFitRect(for: source.size, inside: container)
        landingSheet.draw(
            in: fittedDestination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private func drawMiniListScene(characterIn characterDestination: NSRect, sceneIn sceneDestination: NSRect) {
        let cell = sourceRect(for: 7)
        let split: CGFloat = 0.70
        let mossSource = NSRect(
            x: cell.minX,
            y: cell.minY,
            width: cell.width * split,
            height: cell.height
        )
        let listSource = NSRect(
            x: cell.minX + cell.width * split,
            y: cell.minY,
            width: cell.width * (1 - split),
            height: cell.height
        )
        let mossDestination = NSRect(
            x: characterDestination.minX,
            y: characterDestination.minY,
            width: characterDestination.width * split,
            height: characterDestination.height
        )
        var listDestination = NSRect(
            x: sceneDestination.minX + sceneDestination.width * split,
            y: sceneDestination.minY,
            width: sceneDestination.width * (1 - split),
            height: sceneDestination.height
        )
        listDestination.origin.y += miniListBounceOffset

        spriteSheet.draw(
            in: mossDestination,
            from: mossSource,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        spriteSheet.draw(
            in: listDestination,
            from: listSource,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private func drawIdleMood(in destination: NSRect) {
        guard idleMood == .happy else { return }
        let sheet = happySheet
        let divisor: CGFloat = 0.30
        let frame = Int(bobPhase / divisor) % 4
        let source = stripSourceRect(frame: frame, in: sheet)
        let container = destination.insetBy(dx: -12, dy: -12)
        sheet.draw(
            in: aspectFitRect(for: source.size, inside: container),
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private func drawSleepLifecycle(in destination: NSRect) {
        let sheet: NSImage
        let frame: Int
        if state == .sleeping {
            sheet = sleepSheet
            frame = Int(bobPhase / 0.92) % 4
        } else {
            sheet = wakeSheet
            frame = min(3, Int(wakeProgress * 4))
        }
        let source = stripSourceRect(frame: frame, in: sheet)
        let container = destination.insetBy(dx: -12, dy: -12)
        sheet.draw(
            in: aspectFitRect(for: source.size, inside: container),
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private func sourceRect(for index: Int) -> NSRect {
        let columns: CGFloat = 4
        let rows: CGFloat = 2
        let width = spriteSheet.size.width / columns
        let height = spriteSheet.size.height / rows
        let column = CGFloat(index % 4)
        let topRow = index < 4
        let rowY: CGFloat = topRow ? height : 0
        return NSRect(x: column * width, y: rowY, width: width, height: height)
    }

    private func walkSourceRect(in sheet: NSImage) -> NSRect {
        let frame = Int(bobPhase / 0.36) % 4
        return stripSourceRect(frame: frame, in: sheet)
    }

    private var currentWalkSheet: NSImage {
        switch walkDirection {
        case .side: walkSheet
        case .up: walkUpSheet
        case .down: walkDownSheet
        }
    }

    private func stripSourceRect(frame: Int, in sheet: NSImage) -> NSRect {
        let width = sheet.size.width / 4
        return NSRect(x: CGFloat(frame) * width, y: 0, width: width, height: sheet.size.height)
    }

    private func stripFrameSize(in sheet: NSImage) -> NSSize {
        NSSize(width: sheet.size.width / 4, height: sheet.size.height)
    }

    private func aspectFitRect(for sourceSize: NSSize, inside container: NSRect) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return container }
        let scale = min(container.width / sourceSize.width, container.height / sourceSize.height)
        let size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return NSRect(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private var miniListBounceOffset: CGFloat {
        sin(bobPhase * 1.55) * 3.5
    }

    private var miniListVisualRect: NSRect {
        NSRect(
            x: bounds.width * 0.66,
            y: bounds.height * 0.34 + miniListBounceOffset,
            width: bounds.width * 0.30,
            height: bounds.height * 0.40
        )
    }

    private var miniListAnchorRect: NSRect {
        miniListVisualRect
    }
}
