import AppKit

@MainActor
final class PetWindowController: NSWindowController {
    private let petSize = NSSize(width: 132, height: 132)
    private var movementTimer: Timer?
    private var movementTarget: NSPoint?
    private var pausedUntil = Date.distantPast
    private var stalledMovementTicks = 0
    private var taskPanelController: TaskPanelWindowController?

    init() {
        let window = PetPanel(
            contentRect: NSRect(origin: .zero, size: petSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false

        super.init(window: window)

        let petView = PetView(frame: NSRect(origin: .zero, size: petSize))
        petView.onReminderRequested = { [weak self] in
            self?.pauseWalking()
        }
        petView.onListRequested = { [weak self] anchor in
            self?.showTaskPanel(from: anchor) ?? false
        }
        petView.onPickUp = { [weak self] in
            self?.pauseWalking()
        }
        petView.onDrop = { [weak self] in
            self?.resumeAfterDrop()
        }
        petView.onResumeWalking = { [weak self] in
            self?.startWalking()
        }
        petView.onSleepRequested = { [weak self] in
            self?.pauseWalking()
        }
        petView.onWakeRequested = { [weak self] in
            self?.startWalking()
        }
        petView.onDrag = { [weak self] delta in
            self?.moveWindow(by: delta)
        }
        window.contentView = petView

        placeAtBottomLeft()
        startWalking()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func placeAtBottomLeft() {
        guard let window, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.minX + 24, y: visible.minY + 10))
    }

    private func startWalking() {
        movementTimer?.invalidate()
        movementTarget = nil
        pausedUntil = Date().addingTimeInterval(Double.random(in: 0.4...1.4))
        movementTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(advanceAlongDesktop(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    private func pauseWalking() {
        movementTimer?.invalidate()
        movementTimer = nil
        (window?.contentView as? PetView)?.setWalking(false, horizontal: 0, vertical: 0)
    }

    private func resumeAfterDrop() {
        pausedUntil = Date().addingTimeInterval(Double.random(in: 0.7...1.5))
        startWalking()
    }

    @objc private func advanceAlongDesktop(_ timer: Timer) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let petView = window.contentView as? PetView

        guard Date() >= pausedUntil else {
            petView?.setWalking(false, horizontal: 0, vertical: 0)
            return
        }

        if movementTarget == nil {
            movementTarget = makeRandomTarget(from: window.frame.origin, inside: visible)
        }

        guard let target = movementTarget else { return }
        let origin = window.frame.origin
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = hypot(dx, dy)

        if isTryingToLeaveScreen(from: origin, dx: dx, dy: dy, inside: visible),
           let redirected = inwardTargetIfAtEdge(from: origin, inside: visible) {
            movementTarget = redirected
            stalledMovementTicks = 0
            petView?.setWalking(
                true,
                horizontal: redirected.x - origin.x,
                vertical: redirected.y - origin.y
            )
            return
        }

        guard distance > 2.5 else {
            if let redirected = inwardTargetIfAtEdge(from: origin, inside: visible) {
                movementTarget = redirected
                pausedUntil = Date().addingTimeInterval(0.12)
                petView?.setWalking(
                    true,
                    horizontal: redirected.x - origin.x,
                    vertical: redirected.y - origin.y
                )
                return
            }
            movementTarget = nil
            let takesLongRest = Int.random(in: 0..<100) < 28
            let restDuration = takesLongRest
                ? Double.random(in: 4.0...7.0)
                : Double.random(in: 0.8...3.0)
            pausedUntil = Date().addingTimeInterval(restDuration)
            petView?.setWalking(false, horizontal: dx, vertical: dy)
            return
        }

        let speed: CGFloat = 1.05
        let movingStraightUp = dy > 2.5
        let movingStraightDown = dy < -2.5
        let movingVertically = movingStraightUp || movingStraightDown
        let stepX = movingVertically ? 0 : (dx / distance) * speed
        let stepY = movingStraightUp ? speed : (movingStraightDown ? -speed : (dy / distance) * speed)
        let next = NSPoint(x: origin.x + stepX, y: origin.y + stepY)
        petView?.setWalking(true, horizontal: stepX, vertical: stepY)
        window.setFrameOrigin(next)

        let actualOrigin = window.frame.origin
        if hypot(actualOrigin.x - origin.x, actualOrigin.y - origin.y) < 0.15 {
            stalledMovementTicks += 1
        } else {
            stalledMovementTicks = 0
        }

        if stalledMovementTicks >= 6 {
            movementTarget = inwardRecoveryTarget(from: actualOrigin, inside: visible)
            stalledMovementTicks = 0
        }
    }

    private func isTryingToLeaveScreen(
        from origin: NSPoint,
        dx: CGFloat,
        dy: CGFloat,
        inside visible: NSRect
    ) -> Bool {
        let maxX = visible.maxX - petSize.width
        let maxY = visible.maxY - petSize.height
        let threshold: CGFloat = 3
        return (origin.x <= visible.minX + threshold && dx < 0)
            || (origin.x >= maxX - threshold && dx > 0)
            || (origin.y <= visible.minY + threshold && dy < 0)
            || (origin.y >= maxY - threshold && dy > 0)
    }

    private func inwardRecoveryTarget(from origin: NSPoint, inside visible: NSRect) -> NSPoint {
        let center = NSPoint(
            x: visible.midX - petSize.width / 2,
            y: visible.midY - petSize.height / 2
        )
        let blend = CGFloat.random(in: 0.35...0.65)
        return clampedOrigin(
            NSPoint(
                x: origin.x + (center.x - origin.x) * blend,
                y: origin.y + (center.y - origin.y) * blend
            ),
            inside: visible
        )
    }

    private func inwardTargetIfAtEdge(from origin: NSPoint, inside visible: NSRect) -> NSPoint? {
        let minX = visible.minX
        let maxX = visible.maxX - petSize.width
        let minY = visible.minY
        let maxY = visible.maxY - petSize.height
        let threshold: CGFloat = 3

        let atLeft = origin.x <= minX + threshold
        let atRight = origin.x >= maxX - threshold
        let atBottom = origin.y <= minY + threshold
        let atTop = origin.y >= maxY - threshold
        guard atLeft || atRight || atBottom || atTop else { return nil }

        var target = NSPoint(
            x: origin.x + CGFloat.random(in: -150...150),
            y: origin.y + CGFloat.random(in: -150...150)
        )
        if atLeft {
            target.x = origin.x + CGFloat.random(in: 120...320)
        } else if atRight {
            target.x = origin.x - CGFloat.random(in: 120...320)
        }
        if atBottom {
            target.y = origin.y + CGFloat.random(in: 100...260)
        } else if atTop {
            target.y = origin.y - CGFloat.random(in: 100...260)
        }
        return clampedOrigin(target, inside: visible)
    }

    private func makeRandomTarget(from origin: NSPoint, inside visible: NSRect) -> NSPoint {
        let distance = CGFloat.random(in: 90...360)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let proposed = NSPoint(
            x: origin.x + cos(angle) * distance,
            y: origin.y + sin(angle) * distance
        )
        return clampedOrigin(proposed, inside: visible)
    }

    private func clampedOrigin(_ origin: NSPoint, inside visible: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - petSize.width),
            y: min(max(origin.y, visible.minY), visible.maxY - petSize.height)
        )
    }

    private func moveWindow(by delta: NSPoint) {
        pauseWalking()
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let proposed = NSPoint(
            x: window.frame.origin.x + delta.x,
            y: window.frame.origin.y + delta.y
        )
        window.setFrameOrigin(clampedOrigin(proposed, inside: screen.visibleFrame))
    }

    @discardableResult
    private func showTaskPanel(from anchorInPet: NSRect) -> Bool {
        if let taskPanelController {
            taskPanelController.window?.makeKeyAndOrderFront(nil)
            return true
        }
        guard let petWindow = window else { return false }

        let anchorOnScreen = petWindow.convertToScreen(anchorInPet)
        let controller = TaskPanelWindowController(anchorRect: anchorOnScreen) { [weak self] in
            guard let self else { return }
            self.taskPanelController = nil
            self.window?.orderFrontRegardless()
            (self.window?.contentView as? PetView)?.returnToIdle()
            self.startWalking()
        }
        taskPanelController = controller
        controller.showAnimated()
        pauseWalking()
        petWindow.orderOut(nil)
        return true
    }
}

@MainActor
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
