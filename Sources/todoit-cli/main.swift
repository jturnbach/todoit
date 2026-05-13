import Foundation
import TodoItCore

let args = Array(CommandLine.arguments.dropFirst())
let storage = Storage()

let usageText = """
todoit — add and manage tasks for the TodoIt menubar app

USAGE:
  todoit add <title>... [options]
      --today                    schedule for today (default)
      --tomorrow                 schedule for tomorrow
      --in <N>                   schedule N days from today
      --date YYYY-MM-DD          schedule for a specific date
      --notes <text>             attach notes
      --priority low|normal|high (default: normal)

  todoit list [scope]            list tasks (default: --today)
      --today                    today's open tasks (incl. overdue)
      --upcoming                 future scheduled
      --all                      all open tasks
      --completed                completed tasks

  todoit complete <id-prefix>    mark a task complete
  todoit uncomplete <id-prefix>  re-open a completed task
  todoit remove <id-prefix>      delete a task
  todoit clear-completed         delete all completed tasks
  todoit path                    print path to tasks.json
  todoit help                    show this help

Tasks are stored at:
  ~/Library/Application Support/TodoIt/tasks.json

If the TodoIt menubar app is running, it will pick up changes automatically.
"""

func printUsage() {
    print(usageText)
}

func die(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func parseDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone.current
    f.locale = Locale(identifier: "en_US_POSIX")
    if let d = f.date(from: s) {
        return Calendar.current.startOfDay(for: d)
    }
    return nil
}

func formatDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone.current
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: d)
}

func shortID(_ uuid: UUID) -> String {
    String(uuid.uuidString.prefix(8)).lowercased()
}

func findIndex(in file: TaskFile, matching prefix: String) -> Int? {
    let p = prefix.lowercased()
    let matches = file.tasks.indices.filter { i in
        let id = file.tasks[i].id.uuidString.lowercased()
        return id.hasPrefix(p)
    }
    if matches.count == 1 { return matches[0] }
    if matches.count > 1 {
        FileHandle.standardError.write(Data("error: prefix '\(prefix)' matches \(matches.count) tasks; use more characters\n".utf8))
        exit(2)
    }
    return nil
}

func renderRow(_ t: TodoTask) -> String {
    let mark = t.isCompleted ? "x" : " "
    let prio: String
    switch t.priority {
    case .high: prio = "!"
    case .low: prio = "·"
    case .normal: prio = " "
    }
    return "[\(mark)] \(shortID(t.id)) \(prio) \(formatDate(t.scheduledDate))  \(t.title)"
}

guard let command = args.first else {
    printUsage()
    exit(0)
}

switch command {

case "-h", "--help", "help":
    printUsage()

case "add":
    let rest = Array(args.dropFirst())
    if rest.isEmpty { die("missing task title", code: 2) }

    var titleParts: [String] = []
    var date = Calendar.current.startOfDay(for: Date())
    var notes: String?
    var priority: Priority = .normal

    var i = 0
    while i < rest.count {
        let arg = rest[i]
        switch arg {
        case "--date":
            i += 1
            guard i < rest.count, let d = parseDate(rest[i]) else { die("--date requires YYYY-MM-DD", code: 2) }
            date = d
        case "--today":
            date = Calendar.current.startOfDay(for: Date())
        case "--tomorrow":
            date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        case "--in":
            i += 1
            guard i < rest.count, let n = Int(rest[i]) else { die("--in requires a number of days", code: 2) }
            date = Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: Date()))!
        case "--notes":
            i += 1
            guard i < rest.count else { die("--notes requires a value", code: 2) }
            notes = rest[i]
        case "--priority":
            i += 1
            guard i < rest.count, let p = Priority(rawValue: rest[i].lowercased()) else { die("--priority must be low|normal|high", code: 2) }
            priority = p
        default:
            titleParts.append(arg)
        }
        i += 1
    }

    let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty { die("title is required", code: 2) }

    let task = TodoTask(title: title, notes: notes, scheduledDate: date, priority: priority)
    do {
        try storage.mutate { file in
            file.tasks.append(task)
        }
    } catch { die("failed to save: \(error)") }
    print("added \(shortID(task.id))  \(formatDate(task.scheduledDate))  \(task.title)")

case "list":
    let scope = args.dropFirst().first ?? "--today"
    let file: TaskFile
    do { file = try storage.withLock { try storage.load() } } catch { die("failed to load: \(error)") }
    let today = Calendar.current.startOfDay(for: Date())

    let tasks: [TodoTask]
    switch scope {
    case "--today":
        tasks = file.tasks.filter { !$0.isCompleted && $0.scheduledDate <= today }
    case "--upcoming":
        tasks = file.tasks.filter { !$0.isCompleted && $0.scheduledDate > today }
    case "--all":
        tasks = file.tasks.filter { !$0.isCompleted }
    case "--completed":
        tasks = file.tasks.filter { $0.isCompleted }
    default:
        die("unknown scope '\(scope)'. Use --today | --upcoming | --all | --completed", code: 2)
    }

    if tasks.isEmpty {
        print("(no tasks)")
    } else {
        let sorted = tasks.sorted { a, b in
            if a.scheduledDate != b.scheduledDate { return a.scheduledDate < b.scheduledDate }
            return a.priority.sortOrder < b.priority.sortOrder
        }
        for t in sorted { print(renderRow(t)) }
    }

case "complete":
    guard let prefix = args.dropFirst().first else { die("missing id prefix", code: 2) }
    var changed: TodoTask?
    do {
        try storage.mutate { file in
            guard let idx = findIndex(in: file, matching: prefix) else {
                die("no task matching '\(prefix)'", code: 2)
            }
            file.tasks[idx].isCompleted = true
            file.tasks[idx].completedAt = Date()
            changed = file.tasks[idx]
        }
    } catch { die("failed to save: \(error)") }
    if let t = changed { print("completed \(shortID(t.id))  \(t.title)") }

case "uncomplete":
    guard let prefix = args.dropFirst().first else { die("missing id prefix", code: 2) }
    var changed: TodoTask?
    do {
        try storage.mutate { file in
            guard let idx = findIndex(in: file, matching: prefix) else {
                die("no task matching '\(prefix)'", code: 2)
            }
            file.tasks[idx].isCompleted = false
            file.tasks[idx].completedAt = nil
            changed = file.tasks[idx]
        }
    } catch { die("failed to save: \(error)") }
    if let t = changed { print("reopened \(shortID(t.id))  \(t.title)") }

case "remove":
    guard let prefix = args.dropFirst().first else { die("missing id prefix", code: 2) }
    var removed: TodoTask?
    do {
        try storage.mutate { file in
            guard let idx = findIndex(in: file, matching: prefix) else {
                die("no task matching '\(prefix)'", code: 2)
            }
            removed = file.tasks.remove(at: idx)
        }
    } catch { die("failed to save: \(error)") }
    if let t = removed { print("removed \(shortID(t.id))  \(t.title)") }

case "clear-completed":
    var count = 0
    do {
        try storage.mutate { file in
            let before = file.tasks.count
            file.tasks.removeAll { $0.isCompleted }
            count = before - file.tasks.count
        }
    } catch { die("failed to save: \(error)") }
    print("removed \(count) completed task\(count == 1 ? "" : "s")")

case "path":
    print(AppPaths.tasksFile.path)

default:
    FileHandle.standardError.write(Data("error: unknown command '\(command)'\n".utf8))
    printUsage()
    exit(2)
}
