import AppKit
import SwiftUI

@MainActor
final class PanelMossCelebrationController: ObservableObject {
    fileprivate weak var view: PanelMossView?

    func celebrateCompletedTask() {
        view?.playRandomCelebration()
    }

    func celebrateAllQuestsComplete() {
        view?.playFireworksCelebration()
    }
}

fileprivate final class PanelMossView: NSView {
    private enum Mood {
        case entering
        case walking
        case happy
        case sleeping
        case waking
        case celebrating
        case fireworks
    }

    private let entrySheet: NSImage
    private let celebrationSheets: [NSImage]
    private let fireworksSheet: NSImage
    private let walkSheet: NSImage
    private let happySheet: NSImage
    private let sleepSheet: NSImage
    private let wakeSheet: NSImage
    private var timer: Timer?
    private var mood = Mood.entering
    private var frameIndex = 0
    private var x: CGFloat = 90
    private var direction: CGFloat = 1
    private var ticksInMood = 0
    private var nextRestTick = Int.random(in: 360...600)
    private var celebrationRow = 0
    private var lastCelebrationRow: Int?
    private var hasPendingCelebration = false
    private var hasPendingFireworks = false

    override init(frame frameRect: NSRect) {
        func image(named name: String) -> NSImage {
            let url = Bundle.main.url(forResource: name, withExtension: "png")
                ?? Bundle.module.url(forResource: name, withExtension: "png")
            guard let url, let image = NSImage(contentsOf: url) else {
                fatalError("Missing \(name).png")
            }
            return image
        }

        entrySheet = image(named: "moss-panel-entry")
        celebrationSheets = [
            image(named: "moss-celebrate-hands"),
            image(named: "moss-celebrate-hop"),
            image(named: "moss-celebrate-twirl"),
            image(named: "moss-celebrate-wand"),
            image(named: "moss-celebrate-leaves")
        ]
        fireworksSheet = image(named: "moss-fireworks-cast")
        walkSheet = image(named: "moss-walk")
        happySheet = image(named: "moss-happy")
        sleepSheet = image(named: "moss-sleep")
        wakeSheet = image(named: "moss-wake")
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.advance()
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .none

        let sheet: NSImage
        switch mood {
        case .entering: sheet = entrySheet
        case .celebrating: sheet = celebrationSheets[celebrationRow]
        case .fireworks: sheet = fireworksSheet
        case .walking: sheet = walkSheet
        case .happy: sheet = happySheet
        case .sleeping: sheet = sleepSheet
        case .waking: sheet = wakeSheet
        }

        let source: NSRect
        if mood == .entering {
            let sourceWidth = sheet.size.width / 8
            source = NSRect(
                x: CGFloat(frameIndex) * sourceWidth,
                y: sheet.size.height * 0.12,
                width: sourceWidth,
                height: sheet.size.height * 0.52
            )
        } else if mood == .fireworks {
            let sourceWidth = sheet.size.width / 4
            let sourceHeight = sheet.size.height / 2
            let column = CGFloat(frameIndex % 4)
            let rowY: CGFloat = frameIndex < 4 ? sourceHeight : 0
            source = NSRect(
                x: column * sourceWidth,
                y: rowY,
                width: sourceWidth,
                height: sourceHeight
            )
        } else {
            let sourceWidth = sheet.size.width / 4
            source = NSRect(
                x: CGFloat(frameIndex) * sourceWidth,
                y: 0,
                width: sourceWidth,
                height: sheet.size.height
            )
        }
        // The casting atlas uses square cells, while the walking strip uses
        // tall cells with more transparent padding. A 70-point cast cell
        // produces the same visible hood-to-feet size as the 94-point walk.
        let height: CGFloat = mood == .fireworks ? 70 : 94
        let width = height * source.width / source.height
        let drawX = mood == .entering ? bounds.midX - width / 2 : x
        let entryY: CGFloat
        if frameIndex <= 2 {
            entryY = 30
        } else if frameIndex <= 5 {
            entryY = 17
        } else {
            entryY = 2
        }
        let drawY: CGFloat
        if mood == .entering {
            drawY = entryY
        } else if mood == .fireworks {
            // The square casting cells have less transparent padding below
            // the feet than the tall walking cells. Lift the atlas so Moss's
            // visible foot baseline stays fixed when the spell begins.
            drawY = 10
        } else {
            drawY = -2
        }
        let destination = NSRect(
            x: drawX,
            y: drawY,
            width: width,
            height: height
        )

        let context = NSGraphicsContext.current
        context?.saveGraphicsState()
        if mood == .entering, frameIndex <= 2 {
            // The panel begins 34 points below this overlay. Clipping the
            // lower part of the sprite lets the real panel lip occlude Moss,
            // so the peek reads as coming from behind the list.
            let panelLipY = bounds.height - 34
            NSBezierPath(
                rect: NSRect(
                    x: 0,
                    y: panelLipY - 4,
                    width: bounds.width,
                    height: bounds.height - panelLipY + 4
                )
            ).addClip()
        }
        if direction < 0, mood == .walking {
            let transform = NSAffineTransform()
            transform.translateX(by: destination.midX, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.translateX(by: -destination.midX, yBy: 0)
            transform.concat()
        }
        sheet.draw(
            in: destination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
        if mood == .fireworks {
            drawFireworksEffect(around: destination)
        }
        context?.restoreGraphicsState()
    }

    private func advance() {
        ticksInMood += 1

        switch mood {
        case .entering:
            switch ticksInMood {
            case 0..<60:
                frameIndex = 0       // Two-second pause after expansion.
            case 60..<132:
                frameIndex = 1       // Peek and look for 2.4 seconds.
            case 132..<150:
                frameIndex = 2       // Settle both hands on the edge.
            case 150..<155:
                frameIndex = 3
            case 155..<160:
                frameIndex = 4
            case 160..<165:
                frameIndex = 5
            case 165..<173:
                frameIndex = 6       // Hold the thump for extra weight.
            default:
                frameIndex = 7
            }
            if ticksInMood > 181 {
                x = bounds.midX - 36
                if hasPendingFireworks {
                    hasPendingFireworks = false
                    beginFireworksCelebration()
                } else if hasPendingCelebration {
                    hasPendingCelebration = false
                    beginRandomCelebration()
                } else {
                    startWalkingAgain()
                }
            }
        case .walking:
            frameIndex = (ticksInMood / 5) % 4
            x += direction * 1.05
            let spriteWidth: CGFloat = 72
            if x <= 14 {
                x = 14
                direction = 1
            } else if x >= bounds.width - spriteWidth - 14 {
                x = max(14, bounds.width - spriteWidth - 14)
                direction = -1
            }
            if ticksInMood >= nextRestTick {
                mood = Bool.random() ? .happy : .sleeping
                ticksInMood = 0
            }
        case .happy:
            frameIndex = (ticksInMood / 5) % 4
            if ticksInMood > 70 {
                startWalkingAgain()
            }
        case .sleeping:
            frameIndex = (ticksInMood / 12) % 4
            if ticksInMood > 150 {
                mood = .waking
                ticksInMood = 0
                frameIndex = 0
            }
        case .waking:
            frameIndex = min(3, ticksInMood / 12)
            if ticksInMood > 48 {
                startWalkingAgain()
            }
        case .celebrating:
            frameIndex = min(3, ticksInMood / 8)
            if ticksInMood > 39 {
                startWalkingAgain()
            }
        case .fireworks:
            switch ticksInMood {
            case 0..<8: frameIndex = 0
            case 8..<15: frameIndex = 1
            case 15..<22: frameIndex = 2
            case 22..<29: frameIndex = 3
            case 29..<36: frameIndex = 4
            case 36..<43: frameIndex = 5
            case 43..<50: frameIndex = 6
            default: frameIndex = 7
            }
            if ticksInMood > 122 {
                startWalkingAgain()
            }
        }
        needsDisplay = true
    }

    fileprivate func playRandomCelebration() {
        if mood == .entering {
            hasPendingCelebration = true
            return
        }
        beginRandomCelebration()
    }

    fileprivate func playFireworksCelebration() {
        if mood == .entering {
            hasPendingFireworks = true
            hasPendingCelebration = false
            return
        }
        beginFireworksCelebration()
    }

    private func beginRandomCelebration() {
        var choices = Array(0..<5)
        if let lastCelebrationRow {
            choices.removeAll { $0 == lastCelebrationRow }
        }
        let selected = choices.randomElement() ?? 0
        celebrationRow = selected
        lastCelebrationRow = selected
        mood = .celebrating
        ticksInMood = 0
        frameIndex = 0
        needsDisplay = true
    }

    private func beginFireworksCelebration() {
        mood = .fireworks
        ticksInMood = 0
        frameIndex = 0
        needsDisplay = true
    }

    private func drawFireworksEffect(around destination: NSRect) {
        // Wait until Moss has visibly pulled his arm from the cloak and
        // finished raising the wand before releasing any particles.
        guard ticksInMood >= 50 else { return }
        let colors = [
            NSColor(red: 0.96, green: 0.82, blue: 0.48, alpha: 1),
            NSColor(red: 0.66, green: 0.76, blue: 0.58, alpha: 1),
            NSColor(red: 0.96, green: 0.67, blue: 0.54, alpha: 1),
            NSColor(red: 0.88, green: 0.68, blue: 0.76, alpha: 1)
        ]
        let tip = NSPoint(
            x: destination.minX + destination.width * 0.74,
            y: destination.maxY - 2
        )
        let centers = [
            NSPoint(x: max(18, destination.midX - 43), y: bounds.maxY - 16),
            NSPoint(x: destination.midX - 14, y: bounds.maxY - 6),
            NSPoint(x: destination.midX + 18, y: bounds.maxY - 10),
            NSPoint(x: min(bounds.maxX - 18, destination.midX + 47), y: bounds.maxY - 18)
        ]

        if ticksInMood < 72 {
            let progress = CGFloat(ticksInMood - 50) / 22
            for index in centers.indices {
                colors[index].withAlphaComponent(0.88).setFill()
                for step in 0..<7 {
                    let stepProgress = min(progress * 1.28 - CGFloat(step) * 0.10, 1)
                    guard stepProgress > 0 else { continue }
                    let t = max(0, stepProgress)
                    let x = tip.x + (centers[index].x - tip.x) * t
                    let y = tip.y + (centers[index].y - tip.y) * t
                    let size: CGFloat = step.isMultiple(of: 3) ? 2 : 1.5
                    NSRect(x: round(x), y: round(y), width: size, height: size).fill()
                }
            }
            return
        }

        let directions: [(CGFloat, CGFloat)] = [
            (0, 1), (0.7, 0.7), (1, 0), (0.7, -0.7),
            (0, -1), (-0.7, -0.7), (-1, 0), (-0.7, 0.7)
        ]
        for index in centers.indices {
            let localTick = ticksInMood - 72 - index * 4
            guard localTick >= 0 else { continue }
            let burstProgress = min(CGFloat(localTick) / 18, 1)
            let fade = max(0.10, 1 - CGFloat(max(0, localTick - 22)) / 30)
            let radius = 2 + burstProgress * 13
            colors[index].withAlphaComponent(fade).setFill()
            for (dx, dy) in directions {
                let fall = CGFloat(max(0, localTick - 22)) * 0.14
                let x = centers[index].x + dx * radius
                let y = centers[index].y + dy * radius - fall
                NSRect(x: round(x), y: round(y), width: 2, height: 2).fill()

                if abs(dx) < 0.1 || abs(dy) < 0.1 {
                    NSRect(x: round(x) - 2, y: round(y), width: 6, height: 1).fill()
                    NSRect(x: round(x), y: round(y) - 2, width: 1, height: 6).fill()
                }
            }

            let twinklePulse = CGFloat((localTick / 4) % 2)
            let twinkleSize: CGFloat = twinklePulse == 0 ? 3 : 5
            NSRect(
                x: centers[index].x - twinkleSize / 2,
                y: centers[index].y - 0.5,
                width: twinkleSize,
                height: 1
            ).fill()
            NSRect(
                x: centers[index].x - 0.5,
                y: centers[index].y - twinkleSize / 2,
                width: 1,
                height: twinkleSize
            ).fill()
        }
    }

    private func startWalkingAgain() {
        mood = .walking
        ticksInMood = 0
        frameIndex = 0
        nextRestTick = Int.random(in: 360...600)
    }
}

struct PanelMossCompanionView: NSViewRepresentable {
    let controller: PanelMossCelebrationController

    func makeNSView(context: Context) -> NSView {
        let view = PanelMossView(frame: .zero)
        controller.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
