@preconcurrency import EventKit
import Foundation

@MainActor
final class RemindersSyncService {
    private struct Snapshot: Equatable {
        let title: String
        let isCompleted: Bool
    }

    private weak var store: MossTaskStore?
    private let eventStore = EKEventStore()
    private let listName = "Moss's Quest Log"
    private let legacyListName = "Moss Quest Log"
    private var calendar: EKCalendar?
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var lastSynced: [String: Snapshot] = [:]
    private var isSyncing = false

    init(store: MossTaskStore) {
        self.store = store
    }

    func start() {
        Task { @MainActor [weak self] in
            await self?.requestAccessAndBeginSyncing()
        }
    }

    private func requestAccessAndBeginSyncing() async {
        do {
            guard try await eventStore.requestFullAccessToReminders() else {
                NSLog("Moss Reminders sync: access was not granted")
                return
            }
            guard let calendar = findOrCreateCalendar() else { return }
            self.calendar = calendar

            changeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: eventStore,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.poll()
                }
            }

            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
                guard self != nil else {
                    timer.invalidate()
                    return
                }
                MainActor.assumeIsolated {
                    self?.poll()
                }
            }
            poll()
        } catch {
            NSLog("Moss Reminders sync permission error: \(error)")
        }
    }

    private func findOrCreateCalendar() -> EKCalendar? {
        if let existing = eventStore.calendars(for: .reminder).first(where: {
            $0.title.compare(listName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return existing
        }

        // Preserve the existing list and its Reminder identifiers when
        // upgrading the display name, rather than creating a second list.
        if let legacy = eventStore.calendars(for: .reminder).first(where: {
            $0.title.compare(legacyListName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            legacy.title = listName
            do {
                try eventStore.saveCalendar(legacy, commit: true)
                return legacy
            } catch {
                NSLog("Moss Reminders sync could not rename its list: \(error)")
                return legacy
            }
        }

        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = listName

        let iCloudSource = eventStore.sources.first {
            $0.sourceType == .calDAV
                && $0.title.localizedCaseInsensitiveContains("iCloud")
        }
        newCalendar.source = iCloudSource
            ?? eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local })

        guard newCalendar.source != nil else {
            NSLog("Moss Reminders sync: no writable Reminders account is available")
            return nil
        }

        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            NSLog("Moss Reminders sync could not create its list: \(error)")
            return nil
        }
    }

    private func poll() {
        guard !isSyncing, let calendar else { return }
        isSyncing = true
        let predicate = eventStore.predicateForReminders(in: [calendar])
        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            DispatchQueue.main.async {
                self?.reconcile(reminders ?? [])
            }
        }
    }

    private func reconcile(_ reminders: [EKReminder]) {
        defer { isSyncing = false }
        guard let store, let calendar else { return }

        var tasks = store.tasks
        var remoteByID: [String: EKReminder] = [:]
        for reminder in reminders {
            remoteByID[reminder.calendarItemIdentifier] = reminder
        }

        let currentLocalIDs = Set(tasks.compactMap(\.reminderIdentifier))

        // A quest removed in Moss is removed from the dedicated Reminders list.
        for identifier in Set(lastSynced.keys).subtracting(currentLocalIDs) {
            if let reminder = remoteByID.removeValue(forKey: identifier) {
                do {
                    try eventStore.remove(reminder, commit: true)
                } catch {
                    NSLog("Moss Reminders sync could not delete a reminder: \(error)")
                }
            }
            lastSynced.removeValue(forKey: identifier)
        }

        var taskIndexesToDelete = IndexSet()
        var matchedRemoteIDs = Set<String>()

        for index in tasks.indices {
            guard let identifier = tasks[index].reminderIdentifier else { continue }
            guard let reminder = remoteByID[identifier] else {
                // A persisted Reminder ID that vanished means it was deleted
                // in Reminders, including deletions made while Moss was closed.
                taskIndexesToDelete.insert(index)
                lastSynced.removeValue(forKey: identifier)
                continue
            }

            matchedRemoteIDs.insert(identifier)
            let localSnapshot = snapshot(for: tasks[index])
            let remoteSnapshot = snapshot(for: reminder)
            let baseline = lastSynced[identifier]

            if baseline == nil || remoteSnapshot != baseline {
                apply(reminder: reminder, to: &tasks[index])
                lastSynced[identifier] = snapshot(for: tasks[index])
            } else if localSnapshot != baseline {
                apply(task: tasks[index], to: reminder)
                do {
                    try eventStore.save(reminder, commit: true)
                    lastSynced[identifier] = localSnapshot
                } catch {
                    NSLog("Moss Reminders sync could not update a reminder: \(error)")
                }
            } else {
                lastSynced[identifier] = remoteSnapshot
            }
        }

        tasks.remove(atOffsets: taskIndexesToDelete)

        // Match pre-sync quests by title once, then preserve their Reminder IDs.
        for (identifier, reminder) in remoteByID where !matchedRemoteIDs.contains(identifier) {
            let normalizedRemoteTitle = normalized(reminder.title)
            if let index = tasks.firstIndex(where: {
                $0.reminderIdentifier == nil && normalized($0.title) == normalizedRemoteTitle
            }) {
                tasks[index].reminderIdentifier = identifier
                apply(reminder: reminder, to: &tasks[index])
                lastSynced[identifier] = snapshot(for: tasks[index])
            } else {
                let task = MossTask(
                    title: cleanTitle(reminder.title),
                    completedAt: reminder.isCompleted ? (reminder.completionDate ?? Date()) : nil,
                    reminderIdentifier: identifier
                )
                tasks.append(task)
                lastSynced[identifier] = snapshot(for: task)
            }
        }

        // New Moss quests become native items in the dedicated list.
        for index in tasks.indices where tasks[index].reminderIdentifier == nil {
            let title = cleanTitle(tasks[index].title)
            guard !title.isEmpty else { continue }

            let reminder = EKReminder(eventStore: eventStore)
            reminder.calendar = calendar
            apply(task: tasks[index], to: reminder)
            do {
                try eventStore.save(reminder, commit: true)
                let identifier = reminder.calendarItemIdentifier
                tasks[index].reminderIdentifier = identifier
                lastSynced[identifier] = snapshot(for: tasks[index])
            } catch {
                NSLog("Moss Reminders sync could not create a reminder: \(error)")
            }
        }

        if tasks != store.tasks {
            store.tasks = tasks
        }
    }

    private func apply(reminder: EKReminder, to task: inout MossTask) {
        task.title = cleanTitle(reminder.title)
        task.completedAt = reminder.isCompleted ? (reminder.completionDate ?? task.completedAt ?? Date()) : nil
    }

    private func apply(task: MossTask, to reminder: EKReminder) {
        reminder.title = cleanTitle(task.title)
        reminder.isCompleted = task.completedAt != nil
        reminder.completionDate = task.completedAt
    }

    private func snapshot(for task: MossTask) -> Snapshot {
        Snapshot(title: cleanTitle(task.title), isCompleted: task.completedAt != nil)
    }

    private func snapshot(for reminder: EKReminder) -> Snapshot {
        Snapshot(title: cleanTitle(reminder.title), isCompleted: reminder.isCompleted)
    }

    private func cleanTitle(_ title: String?) -> String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ title: String?) -> String {
        cleanTitle(title).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
