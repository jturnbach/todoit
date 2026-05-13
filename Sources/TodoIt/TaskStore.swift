import Foundation
import Combine
import TodoItCore

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var tasks: [TodoTask] = []

    private let storage = Storage()
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    private init() {
        ensureFileExists()
        reload()
        startWatching()
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: AppPaths.tasksFile.path) {
            try? storage.save(TaskFile())
        }
    }

    func reload() {
        do {
            let file = try storage.withLock { try storage.load() }
            self.tasks = file.tasks
        } catch {
            NSLog("TodoIt: failed to load tasks: \(error)")
        }
    }

    private func save() {
        let snapshot = tasks
        do {
            try storage.withLock {
                try storage.save(TaskFile(tasks: snapshot))
            }
        } catch {
            NSLog("TodoIt: failed to save tasks: \(error)")
        }
    }

    private func startWatching() {
        ensureFileExists()
        let fd = open(AppPaths.tasksFile.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("TodoIt: could not open tasks.json for watching")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitor = source
    }

    private func handleFileChange() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reload()
            self.fileMonitor?.cancel()
            self.fileMonitor = nil
            self.startWatching()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Mutations

    func add(_ task: TodoTask) {
        tasks.append(task)
        save()
    }

    func update(_ task: TodoTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
            save()
        }
    }

    func toggleComplete(_ id: TodoTask.ID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isCompleted.toggle()
        tasks[idx].completedAt = tasks[idx].isCompleted ? Date() : nil
        save()
    }

    func remove(_ id: TodoTask.ID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        tasks.removeAll { $0.isCompleted }
        save()
    }

    // MARK: - Queries

    var todayAndOverdue: [TodoTask] {
        let today = Calendar.current.startOfDay(for: Date())
        return tasks
            .filter { !$0.isCompleted && $0.scheduledDate <= today }
            .sorted(by: ordering)
    }

    var upcoming: [TodoTask] {
        let today = Calendar.current.startOfDay(for: Date())
        return tasks
            .filter { !$0.isCompleted && $0.scheduledDate > today }
            .sorted(by: ordering)
    }

    var activeAll: [TodoTask] {
        tasks
            .filter { !$0.isCompleted }
            .sorted(by: ordering)
    }

    var completed: [TodoTask] {
        tasks
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func ordering(_ a: TodoTask, _ b: TodoTask) -> Bool {
        if a.scheduledDate != b.scheduledDate { return a.scheduledDate < b.scheduledDate }
        if a.priority != b.priority { return a.priority.sortOrder < b.priority.sortOrder }
        return a.createdAt < b.createdAt
    }
}
