import AppKit
import SwiftUI

@MainActor
final class TaskPanelWindowController: NSWindowController {
    private let anchorRect: NSRect
    private let onClose: () -> Void
    private let panelSize = NSSize(width: 520, height: 530)
    private let minimumPanelSize = NSSize(width: 430, height: 440)

    init(anchorRect: NSRect, onClose: @escaping () -> Void) {
        self.anchorRect = anchorRect
        self.onClose = onClose

        let panel = InteractivePanel(
            contentRect: anchorRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.minSize = minimumPanelSize
        panel.contentMinSize = minimumPanelSize

        super.init(window: panel)

        let rootView = MossTaskPanel(onClose: { [weak self] in
            self?.closeAnimated()
        })
        panel.contentViewController = NSHostingController(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showAnimated() {
        guard let window else { return }
        let destination = destinationFrame()
        window.alphaValue = 0
        window.setFrame(anchorRect, display: false)
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(destination, display: true)
        }
    }

    private func closeAnimated() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(anchorRect, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window?.orderOut(nil)
                self.onClose()
            }
        }
    }

    private func destinationFrame() -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorRect) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(
            x: anchorRect.midX - panelSize.width / 2,
            y: anchorRect.midY - panelSize.height / 2
        )
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - panelSize.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - panelSize.height - 12)
        return NSRect(origin: origin, size: panelSize)
    }
}

@MainActor
final class InteractivePanel: NSPanel {
    private struct ResizeEdges: OptionSet {
        let rawValue: Int

        static let left = ResizeEdges(rawValue: 1 << 0)
        static let right = ResizeEdges(rawValue: 1 << 1)
        static let bottom = ResizeEdges(rawValue: 1 << 2)
        static let top = ResizeEdges(rawValue: 1 << 3)
    }

    private let resizeHitWidth: CGFloat = 10
    private var activeResizeEdges: ResizeEdges?
    private var resizeStartFrame = NSRect.zero
    private var resizeStartMouse = NSPoint.zero

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let edges = resizeEdges(at: event.locationInWindow)
            if !edges.isEmpty {
                activeResizeEdges = edges
                resizeStartFrame = frame
                resizeStartMouse = NSEvent.mouseLocation
                return
            }
        case .leftMouseDragged:
            if let edges = activeResizeEdges {
                resize(using: edges, mouse: NSEvent.mouseLocation)
                return
            }
        case .leftMouseUp:
            if activeResizeEdges != nil {
                activeResizeEdges = nil
                return
            }
        case .mouseMoved:
            updateResizeCursor(at: event.locationInWindow)
        default:
            break
        }

        super.sendEvent(event)
    }

    private func resizeEdges(at point: NSPoint) -> ResizeEdges {
        var edges: ResizeEdges = []
        if point.x <= resizeHitWidth { edges.insert(.left) }
        if point.x >= frame.width - resizeHitWidth { edges.insert(.right) }
        if point.y <= resizeHitWidth { edges.insert(.bottom) }
        if point.y >= frame.height - resizeHitWidth { edges.insert(.top) }
        return edges
    }

    private func resize(using edges: ResizeEdges, mouse: NSPoint) {
        let dx = mouse.x - resizeStartMouse.x
        let dy = mouse.y - resizeStartMouse.y
        var next = resizeStartFrame

        if edges.contains(.left) {
            next.origin.x = resizeStartFrame.minX + dx
            next.size.width = resizeStartFrame.width - dx
        } else if edges.contains(.right) {
            next.size.width = resizeStartFrame.width + dx
        }

        if edges.contains(.bottom) {
            next.origin.y = resizeStartFrame.minY + dy
            next.size.height = resizeStartFrame.height - dy
        } else if edges.contains(.top) {
            next.size.height = resizeStartFrame.height + dy
        }

        if next.width < minSize.width {
            if edges.contains(.left) {
                next.origin.x = resizeStartFrame.maxX - minSize.width
            }
            next.size.width = minSize.width
        }
        if next.height < minSize.height {
            if edges.contains(.bottom) {
                next.origin.y = resizeStartFrame.maxY - minSize.height
            }
            next.size.height = minSize.height
        }

        setFrame(next, display: true)
    }

    private func updateResizeCursor(at point: NSPoint) {
        let edges = resizeEdges(at: point)
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)

        if horizontal {
            NSCursor.resizeLeftRight.set()
        } else if vertical {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

private struct MossTaskPanel: View {
    private enum Tab {
        case active
        case archived
    }

    let onClose: () -> Void

    @StateObject private var store = MossTaskStore.shared
    @StateObject private var celebrationController = PanelMossCelebrationController()
    @State private var selectedTab = Tab.active
    @State private var editingTaskID: UUID?
    @FocusState private var focusedTaskID: UUID?

    private let paper = Color(red: 0.97, green: 0.93, blue: 0.84)
    private let rowPaper = Color(red: 0.99, green: 0.96, blue: 0.88)
    private let tan = Color(red: 0.76, green: 0.58, blue: 0.40)
    private let cocoa = Color(red: 0.24, green: 0.16, blue: 0.12)
    private let buttonBrown = Color(red: 0.48, green: 0.32, blue: 0.23)

    var body: some View {
        ZStack(alignment: .top) {
            panelContent
                .padding(.horizontal, 30)
                .padding(.top, 62)
                .padding(.bottom, 22)
                .foregroundStyle(cocoa)
                .background(panelBackground)
                .padding(.top, 34)

            PanelMossCompanionView(controller: celebrationController)
                .frame(height: 104)
                .accessibilityLabel("Moss walking along the task list")
        }
        .padding(6)
        .frame(minWidth: 430, minHeight: 440)
        .onChange(of: editingTaskID) { oldTaskID, newTaskID in
            if let oldTaskID, oldTaskID != newTaskID {
                store.removeIfBlank(oldTaskID)
            }
        }
        .onDisappear {
            store.removeBlankTasks()
        }
    }

    private var panelContent: some View {
        VStack(spacing: 10) {
            panelHeader
            tabBar
            if selectedTab == .active {
                activeTaskList
                addQuestButton
            } else {
                archivedTaskList
                Text("COMPLETED QUESTS VANISH AFTER 2 DAYS")
                    .font(pixelFont(size: 16))
                    .foregroundStyle(buttonBrown)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var panelHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text("MOSS'S QUEST LOG")
                    .font(pixelFont(size: 16))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)

            Button(action: onClose) {
                Text("X")
                    .font(pixelFont(size: 16))
                    .frame(width: 30, height: 28)
                    .background(paper)
                    .overlay(Rectangle().stroke(cocoa, lineWidth: 3))
            }
            .buttonStyle(.plain)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("ACTIVE", tab: .active, count: store.activeTasks.count)
            tabButton("ARCHIVED", tab: .archived, count: store.archivedTasks.count)
        }
        .overlay(Rectangle().stroke(cocoa, lineWidth: 3))
    }

    private func tabButton(_ title: String, tab: Tab, count: Int) -> some View {
        Button {
            if tab != .active {
                finishEditing()
            }
            store.purgeExpiredTasks()
            selectedTab = tab
        } label: {
            Text("\(title) \(count)")
                .font(pixelFont(size: 16))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(selectedTab == tab ? .white : cocoa)
                .background(selectedTab == tab ? buttonBrown : rowPaper)
        }
        .buttonStyle(.plain)
    }

    private var activeTaskList: some View {
        Group {
            if store.activeTasks.isEmpty {
                emptyState("ALL QUESTS COMPLETE!")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(store.activeTasks) { task in
                                activeTaskRow(task)
                                    .id(task.id)
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: editingTaskID) { _, taskID in
                        guard let taskID else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(taskID, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 100, maxHeight: .infinity)
    }

    private func activeTaskRow(_ task: MossTask) -> some View {
        HStack(spacing: 11) {
            Button {
                var didComplete = false
                withAnimation(.easeOut(duration: 0.16)) {
                    didComplete = store.archive(task.id)
                }
                if didComplete {
                    if store.activeTasks.isEmpty {
                        celebrationController.celebrateAllQuestsComplete()
                    } else {
                        celebrationController.celebrateCompletedTask()
                    }
                }
            } label: {
                Rectangle()
                    .fill(paper)
                    .frame(width: 24, height: 24)
                    .overlay(Rectangle().stroke(cocoa, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .help("Complete and archive this quest")

            Group {
                if editingTaskID == task.id {
                    TextField("NEW QUEST", text: store.binding(for: task.id))
                        .textFieldStyle(.plain)
                        .font(pixelFont(size: 16))
                        .foregroundStyle(cocoa)
                        .focused($focusedTaskID, equals: task.id)
                        .onAppear {
                            focusEditor(for: task.id)
                        }
                        .onSubmit {
                            finishEditing(task.id)
                        }
                } else {
                    HoverMarqueeText(
                        text: task.title.isEmpty ? "NEW QUEST" : task.title,
                        color: cocoa
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginEditing(task.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(rowPaper)
        .overlay(PixelCutCornerShape(cut: 6).stroke(tan, lineWidth: 6))
        .overlay(PixelCutCornerShape(cut: 6).stroke(cocoa, lineWidth: 2))
        .clipShape(PixelCutCornerShape(cut: 6))
    }

    private var archivedTaskList: some View {
        Group {
            if store.archivedTasks.isEmpty {
                emptyState("NO ARCHIVED QUESTS")
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.archivedTasks) { task in
                            archivedTaskRow(task)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(minHeight: 100, maxHeight: .infinity)
    }

    private func archivedTaskRow(_ task: MossTask) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HoverMarqueeText(
                    text: task.title.isEmpty ? "UNTITLED QUEST" : task.title,
                    color: cocoa,
                    strikethrough: true
                )
                Text(store.remainingArchiveTime(for: task))
                    .font(pixelFont(size: 16))
                    .foregroundStyle(buttonBrown)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Button("RESTORE") {
                    withAnimation(.easeOut(duration: 0.16)) {
                        store.restore(task.id)
                    }
                }
                .font(pixelFont(size: 16))
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
                .frame(height: 30)
                .foregroundStyle(.white)
                .background(buttonBrown)
                .overlay(Rectangle().stroke(cocoa, lineWidth: 2))

                Button("DELETE") {
                    withAnimation(.easeOut(duration: 0.16)) {
                        store.delete(task.id)
                    }
                }
                .font(pixelFont(size: 16))
                .buttonStyle(.plain)
                .padding(.horizontal, 7)
                .frame(height: 30)
                .foregroundStyle(cocoa)
                .background(tan.opacity(0.36))
                .overlay(Rectangle().stroke(cocoa, lineWidth: 2))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 54)
        .background(rowPaper)
        .overlay(PixelCutCornerShape(cut: 6).stroke(tan, lineWidth: 6))
        .overlay(PixelCutCornerShape(cut: 6).stroke(cocoa, lineWidth: 2))
        .clipShape(PixelCutCornerShape(cut: 6))
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(pixelFont(size: 16))
            .foregroundStyle(buttonBrown)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addQuestButton: some View {
        Button {
            selectedTab = .active
            let taskID = store.addTask()
            beginEditing(taskID)
        } label: {
            HStack(spacing: 8) {
                Text("+")
                    .font(pixelFont(size: 16))
                Text("ADD QUEST")
                    .font(pixelFont(size: 16))
            }
            .frame(width: 220, height: 44)
            .foregroundStyle(.white)
            .background(buttonBrown)
            .overlay(Rectangle().stroke(cocoa, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(store.activeTasks.count >= 50)
        .opacity(store.activeTasks.count >= 50 ? 0.55 : 1)
    }

    private func beginEditing(_ taskID: UUID) {
        editingTaskID = taskID
        focusEditor(for: taskID)
    }

    private func focusEditor(for taskID: UUID) {
        DispatchQueue.main.async {
            guard editingTaskID == taskID else { return }
            focusedTaskID = taskID
        }
    }

    private func finishEditing(_ taskID: UUID? = nil) {
        let taskID = taskID ?? editingTaskID
        focusedTaskID = nil
        editingTaskID = nil
        if let taskID {
            store.removeIfBlank(taskID)
        }
    }

    private var panelBackground: some View {
        ZStack {
            PixelCutCornerShape(cut: 14)
                .fill(paper)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.28),
                    tan.opacity(0.08),
                    buttonBrown.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            PixelPaperTexture(color: cocoa.opacity(0.055))
        }
            .clipShape(PixelCutCornerShape(cut: 14))
            .shadow(color: cocoa.opacity(0.28), radius: 0, x: 7, y: 7)
            .overlay {
                PixelCutCornerShape(cut: 14)
                    .stroke(tan, lineWidth: 9)
            }
            .overlay {
                PixelCutCornerShape(cut: 14)
                    .stroke(cocoa, lineWidth: 4)
            }
    }

    private func pixelFont(size: CGFloat) -> Font {
        .custom(MossFonts.pixelPostScriptName, fixedSize: size)
    }
}

private struct HoverMarqueeText: View {
    let text: String
    let color: Color
    var strikethrough = false

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isHovering = false
    @State private var marqueeTask: Task<Void, Never>?

    private var overflowDistance: CGFloat {
        max(0, textWidth - containerWidth)
    }

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(.custom(MossFonts.pixelPostScriptName, fixedSize: 16))
                .foregroundStyle(color)
                .strikethrough(strikethrough, color: color.opacity(0.5))
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MarqueeTextWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                }
                .frame(height: proxy.size.height, alignment: .center)
                .offset(x: offset)
                .onAppear {
                    updateContainerWidth(proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, width in
                    updateContainerWidth(width)
                }
        }
        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { width in
            textWidth = width
            reevaluateMarquee()
        }
        .onHover { hovering in
            isHovering = hovering
            reevaluateMarquee()
        }
        .onDisappear {
            marqueeTask?.cancel()
        }
        .accessibilityLabel(text)
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard abs(containerWidth - width) > 0.5 else { return }
        containerWidth = width
        reevaluateMarquee()
    }

    private func reevaluateMarquee() {
        marqueeTask?.cancel()

        guard isHovering, overflowDistance > 1 else {
            withAnimation(.easeOut(duration: 0.18)) {
                offset = 0
            }
            return
        }

        offset = 0
        let distance = overflowDistance + 8
        let duration = max(2.6, Double(distance / 20))
        marqueeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, isHovering, overflowDistance > 1 else { return }
            withAnimation(.linear(duration: duration)) {
                offset = -distance
            }
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PixelPaperTexture: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            var x: CGFloat = 0
            while x <= size.width {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                    with: .color(color)
                )
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(color)
                )
                y += spacing
            }

            var dotY: CGFloat = 8
            var row = 0
            while dotY < size.height {
                var dotX: CGFloat = row.isMultiple(of: 2) ? 8 : 16
                while dotX < size.width {
                    context.fill(
                        Path(CGRect(x: dotX, y: dotY, width: 2, height: 2)),
                        with: .color(color.opacity(0.7))
                    )
                    dotX += 32
                }
                dotY += 32
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PixelCutCornerShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        let amount = min(cut, min(rect.width, rect.height) / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + amount, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + amount))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - amount))
        path.addLine(to: CGPoint(x: rect.maxX - amount, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + amount, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - amount))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + amount))
        path.closeSubpath()
        return path
    }
}
