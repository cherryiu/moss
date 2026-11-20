import Foundation
import SwiftUI

struct MossTask: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var completedAt: Date?
    var reminderIdentifier: String?

    init(
        id: UUID = UUID(),
        title: String,
        completedAt: Date? = nil,
        reminderIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.completedAt = completedAt
        self.reminderIdentifier = reminderIdentifier
    }
}

@MainActor
final class MossTaskStore: ObservableObject {
    static let shared = MossTaskStore()

    @Published var tasks: [MossTask] {
        didSet { persist() }
    }

    private let defaultsKey = "moss.tasks.v1"
    private let archiveLifetime: TimeInterval = 2 * 24 * 60 * 60
    private var purgeTimer: Timer?
    private var remindersSyncService: RemindersSyncService?

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([MossTask].self, from: data) {
            tasks = decoded
        } else {
            tasks = [
                MossTask(title: "Water the plants"),
                MossTask(title: "Reply to messages"),
                MossTask(title: "Take a little stretch"),
                MossTask(title: "Plan tomorrow")
            ]
        }

        purgeExpiredTasks()
        purgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.purgeExpiredTasks()
            }
        }
    }

    var activeTasks: [MossTask] {
        tasks.filter { $0.completedAt == nil }
    }

    var archivedTasks: [MossTask] {
        tasks
            .filter { $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func startRemindersSync() {
        guard remindersSyncService == nil else { return }
        let service = RemindersSyncService(store: self)
        remindersSyncService = service
        service.start()
    }

    func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.tasks.first(where: { $0.id == id })?.title ?? ""
            },
            set: { [weak self] newTitle in
                guard let self,
                      let index = self.tasks.firstIndex(where: { $0.id == id }) else { return }
                self.tasks[index].title = newTitle
            }
        )
    }

    @discardableResult
    func addTask() -> UUID {
        let task = MossTask(title: "")
        tasks.insert(task, at: 0)
        return task.id
    }

    @discardableResult
    func archive(_ id: UUID) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        if tasks[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tasks.remove(at: index)
            return false
        }
        tasks[index].completedAt = Date()
        return true
    }

    func restore(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completedAt = nil
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    func removeIfBlank(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }),
              task.completedAt == nil,
              task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        delete(id)
    }

    func removeBlankTasks() {
        tasks.removeAll { task in
            task.completedAt == nil
                && task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func purgeExpiredTasks(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-archiveLifetime)
        let remaining = tasks.filter { task in
            guard let completedAt = task.completedAt else { return true }
            return completedAt > cutoff
        }
        if remaining != tasks {
            tasks = remaining
        }
    }

    func remainingArchiveTime(for task: MossTask, now: Date = Date()) -> String {
        guard let completedAt = task.completedAt else { return "" }
        let remaining = max(0, archiveLifetime - now.timeIntervalSince(completedAt))
        let hours = max(1, Int(ceil(remaining / 3600)))
        return hours >= 24 ? "DELETES IN \(Int(ceil(Double(hours) / 24)))D" : "DELETES IN \(hours)H"
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
