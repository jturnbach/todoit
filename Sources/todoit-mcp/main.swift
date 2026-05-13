import Foundation
import TodoItCore

// MCP server for TodoIt. Speaks JSON-RPC 2.0 over stdio, newline-delimited.
// Spec: https://spec.modelcontextprotocol.io/specification/2024-11-05/

// MARK: - Logging (stderr only — stdout is reserved for the protocol)

func log(_ msg: String) {
    FileHandle.standardError.write(Data("[todoit-mcp] \(msg)\n".utf8))
}

// MARK: - I/O

func writeMessage(_ object: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        var line = data
        line.append(0x0A)
        FileHandle.standardOutput.write(line)
    } catch {
        log("serialize error: \(error)")
    }
}

// MARK: - JSON-RPC response builders

func successResponse(id: Any, result: [String: Any]) -> [String: Any] {
    return [
        "jsonrpc": "2.0",
        "id": id,
        "result": result
    ]
}

func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
    return [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "error": [
            "code": code,
            "message": message
        ]
    ]
}

func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
    var result: [String: Any] = [
        "content": [["type": "text", "text": text]]
    ]
    if isError {
        result["isError"] = true
    }
    return result
}

// MARK: - Date / formatting

func parseDateArg(_ value: Any?) -> Date? {
    guard let raw = value as? String else { return nil }
    let s = raw.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { return nil }
    let lower = s.lowercased()
    let today = Calendar.current.startOfDay(for: Date())

    switch lower {
    case "today":     return today
    case "tomorrow":  return Calendar.current.date(byAdding: .day, value: 1, to: today)
    case "yesterday": return Calendar.current.date(byAdding: .day, value: -1, to: today)
    default: break
    }

    if lower.hasPrefix("+"), let n = Int(lower.dropFirst()) {
        return Calendar.current.date(byAdding: .day, value: n, to: today)
    }

    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    if let d = f.date(from: s) {
        return Calendar.current.startOfDay(for: d)
    }
    return nil
}

func formatDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    return f.string(from: d)
}

func shortID(_ uuid: UUID) -> String {
    String(uuid.uuidString.prefix(8)).lowercased()
}

func describe(_ t: TodoTask) -> String {
    let today = Calendar.current.startOfDay(for: Date())
    let dateLabel: String
    if t.scheduledDate < today {
        dateLabel = "overdue from \(formatDate(t.scheduledDate))"
    } else if t.scheduledDate == today {
        dateLabel = "today"
    } else if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today),
              t.scheduledDate == tomorrow {
        dateLabel = "tomorrow"
    } else {
        dateLabel = formatDate(t.scheduledDate)
    }
    let mark = t.isCompleted ? "✓" : "•"
    let prio = t.priority == .normal ? "" : " [\(t.priority.rawValue) priority]"
    var line = "\(mark) [\(shortID(t.id))] \(t.title) — \(dateLabel)\(prio)"
    if let n = t.notes, !n.isEmpty {
        line += "\n    Notes: \(n)"
    }
    return line
}

// MARK: - Storage helpers

let storage = Storage()

enum ToolError: Error, CustomStringConvertible {
    case invalidArgs(String)
    case notFound(String)
    case ambiguous(String, Int)
    var description: String {
        switch self {
        case .invalidArgs(let s): return s
        case .notFound(let s): return s
        case .ambiguous(let p, let n): return "ID prefix '\(p)' matches \(n) tasks — use a longer prefix."
        }
    }
}

func resolveTaskIndex(in file: TaskFile, matching idArg: String) throws -> Int {
    let p = idArg.lowercased()
    let matches = file.tasks.indices.filter { file.tasks[$0].id.uuidString.lowercased().hasPrefix(p) }
    switch matches.count {
    case 0: throw ToolError.notFound("No task matching id '\(idArg)'")
    case 1: return matches[0]
    default: throw ToolError.ambiguous(idArg, matches.count)
    }
}

// MARK: - Tool definitions (served via tools/list)

let toolDefinitions: [[String: Any]] = [
    [
        "name": "add_task",
        "description": "Add a new task to the user's TodoIt menubar app. Tasks scheduled for a future date stay hidden from 'today' until that date arrives, which makes this great for capturing things the user mentions in passing but doesn't want to act on right now. Always pass a clear, imperative title.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Short imperative title, e.g. 'Reply to Sarah's email' or 'Prep board deck'."
                ],
                "date": [
                    "type": "string",
                    "description": "When to schedule it. Accepts 'today', 'tomorrow', a YYYY-MM-DD date, or a relative offset like '+3' (3 days from today). Defaults to today."
                ],
                "notes": [
                    "type": "string",
                    "description": "Optional longer-form notes shown when the task is opened in the main window."
                ],
                "priority": [
                    "type": "string",
                    "enum": ["low", "normal", "high"],
                    "description": "Priority. Defaults to normal. Use 'high' only when the user signals urgency."
                ]
            ],
            "required": ["title"]
        ]
    ],
    [
        "name": "list_tasks",
        "description": "Read the user's task board. Use 'today' to see what's on their plate right now (includes overdue), 'upcoming' for future-scheduled tasks, 'all' for everything still open, or 'completed' for the history.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "scope": [
                    "type": "string",
                    "enum": ["today", "upcoming", "all", "completed"],
                    "description": "Which slice of tasks to return. Defaults to 'today'."
                ]
            ]
        ]
    ],
    [
        "name": "complete_task",
        "description": "Mark an existing task as done. The task disappears from 'today' and moves to 'completed'.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": [
                    "type": "string",
                    "description": "Task ID. Accepts the full UUID or a unique 8-character prefix shown by list_tasks (e.g. 'a1b2c3d4')."
                ]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "uncomplete_task",
        "description": "Re-open a previously completed task. Useful if the user changed their mind.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task ID or unique prefix."]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "remove_task",
        "description": "Permanently delete a task. Only use when the user wants the task gone (e.g. they no longer plan to do it). Prefer complete_task when they finished it.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Task ID or unique prefix."]
            ],
            "required": ["id"]
        ]
    ],
    [
        "name": "update_task",
        "description": "Edit an existing task. Pass only the fields you want to change. Reschedule by setting date, or change title/notes/priority.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id":       ["type": "string", "description": "Task ID or unique prefix."],
                "title":    ["type": "string", "description": "Replacement title."],
                "notes":    ["type": "string", "description": "Replacement notes. Pass empty string to clear."],
                "date":     ["type": "string", "description": "today | tomorrow | YYYY-MM-DD | +N"],
                "priority": ["type": "string", "enum": ["low", "normal", "high"]]
            ],
            "required": ["id"]
        ]
    ]
]

// MARK: - Tool handlers

func handleAddTask(_ args: [String: Any]) throws -> String {
    guard let raw = args["title"] as? String else { throw ToolError.invalidArgs("title is required") }
    let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty { throw ToolError.invalidArgs("title cannot be empty") }

    let date = parseDateArg(args["date"]) ?? Calendar.current.startOfDay(for: Date())
    let trimmedNotes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let notes = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
    let priority = (args["priority"] as? String).flatMap { Priority(rawValue: $0.lowercased()) } ?? .normal

    let task = TodoTask(title: title, notes: notes, scheduledDate: date, priority: priority)
    try storage.withLock {
        var file = try storage.load()
        file.tasks.append(task)
        try storage.save(file)
    }
    return "Added: \(describe(task))"
}

func handleListTasks(_ args: [String: Any]) throws -> String {
    let scope = (args["scope"] as? String)?.lowercased() ?? "today"
    let file = try storage.withLock { try storage.load() }
    let today = Calendar.current.startOfDay(for: Date())

    let tasks: [TodoTask]
    let label: String
    switch scope {
    case "today":
        tasks = file.tasks.filter { !$0.isCompleted && $0.scheduledDate <= today }
        label = "today"
    case "upcoming":
        tasks = file.tasks.filter { !$0.isCompleted && $0.scheduledDate > today }
        label = "upcoming"
    case "all":
        tasks = file.tasks.filter { !$0.isCompleted }
        label = "open"
    case "completed":
        tasks = file.tasks.filter { $0.isCompleted }
        label = "completed"
    default:
        throw ToolError.invalidArgs("scope must be 'today', 'upcoming', 'all', or 'completed'")
    }

    if tasks.isEmpty { return "No \(label) tasks." }

    let sorted = tasks.sorted { a, b in
        if a.scheduledDate != b.scheduledDate { return a.scheduledDate < b.scheduledDate }
        return a.priority.sortOrder < b.priority.sortOrder
    }
    let lines = sorted.map(describe).joined(separator: "\n")
    return "\(tasks.count) \(label) task\(tasks.count == 1 ? "" : "s"):\n\(lines)"
}

func handleCompleteTask(_ args: [String: Any]) throws -> String {
    guard let id = args["id"] as? String else { throw ToolError.invalidArgs("id is required") }
    let t = try storage.withLock { () -> TodoTask in
        var file = try storage.load()
        let idx = try resolveTaskIndex(in: file, matching: id)
        file.tasks[idx].isCompleted = true
        file.tasks[idx].completedAt = Date()
        try storage.save(file)
        return file.tasks[idx]
    }
    return "Completed: \(t.title)"
}

func handleUncompleteTask(_ args: [String: Any]) throws -> String {
    guard let id = args["id"] as? String else { throw ToolError.invalidArgs("id is required") }
    let t = try storage.withLock { () -> TodoTask in
        var file = try storage.load()
        let idx = try resolveTaskIndex(in: file, matching: id)
        file.tasks[idx].isCompleted = false
        file.tasks[idx].completedAt = nil
        try storage.save(file)
        return file.tasks[idx]
    }
    return "Re-opened: \(t.title)"
}

func handleRemoveTask(_ args: [String: Any]) throws -> String {
    guard let id = args["id"] as? String else { throw ToolError.invalidArgs("id is required") }
    let t = try storage.withLock { () -> TodoTask in
        var file = try storage.load()
        let idx = try resolveTaskIndex(in: file, matching: id)
        let removed = file.tasks.remove(at: idx)
        try storage.save(file)
        return removed
    }
    return "Removed: \(t.title)"
}

func handleUpdateTask(_ args: [String: Any]) throws -> String {
    guard let id = args["id"] as? String else { throw ToolError.invalidArgs("id is required") }
    let t = try storage.withLock { () -> TodoTask in
        var file = try storage.load()
        let idx = try resolveTaskIndex(in: file, matching: id)
        if let raw = args["title"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { file.tasks[idx].title = trimmed }
        }
        if let raw = args["notes"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            file.tasks[idx].notes = trimmed.isEmpty ? nil : trimmed
        }
        if let d = parseDateArg(args["date"]) {
            file.tasks[idx].scheduledDate = d
        }
        if let p = (args["priority"] as? String).flatMap({ Priority(rawValue: $0.lowercased()) }) {
            file.tasks[idx].priority = p
        }
        try storage.save(file)
        return file.tasks[idx]
    }
    return "Updated: \(describe(t))"
}

// MARK: - Dispatcher

func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
    do {
        let text: String
        switch name {
        case "add_task":        text = try handleAddTask(arguments)
        case "list_tasks":      text = try handleListTasks(arguments)
        case "complete_task":   text = try handleCompleteTask(arguments)
        case "uncomplete_task": text = try handleUncompleteTask(arguments)
        case "remove_task":     text = try handleRemoveTask(arguments)
        case "update_task":     text = try handleUpdateTask(arguments)
        default:
            return toolResult("Unknown tool: \(name)", isError: true)
        }
        return toolResult(text)
    } catch let e as ToolError {
        return toolResult("Error: \(e)", isError: true)
    } catch {
        return toolResult("Error: \(error)", isError: true)
    }
}

// MARK: - Message dispatch

func handle(_ message: [String: Any]) {
    let method = message["method"] as? String
    let id = message["id"]

    switch method {

    case "initialize":
        let clientVersion = (message["params"] as? [String: Any])?["protocolVersion"] as? String
        let result: [String: Any] = [
            "protocolVersion": clientVersion ?? "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": [
                "name": "todoit",
                "version": "1.0.0"
            ]
        ]
        if let id = id { writeMessage(successResponse(id: id, result: result)) }

    case "notifications/initialized",
         "notifications/cancelled",
         "notifications/progress",
         "notifications/roots/list_changed":
        return

    case "ping":
        if let id = id { writeMessage(successResponse(id: id, result: [:])) }

    case "tools/list":
        if let id = id {
            writeMessage(successResponse(id: id, result: ["tools": toolDefinitions]))
        }

    case "tools/call":
        guard let id = id else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        writeMessage(successResponse(id: id, result: callTool(name: name, arguments: args)))

    case "resources/list":
        if let id = id { writeMessage(successResponse(id: id, result: ["resources": []])) }

    case "prompts/list":
        if let id = id { writeMessage(successResponse(id: id, result: ["prompts": []])) }

    default:
        if let id = id {
            writeMessage(errorResponse(id: id, code: -32601, message: "Method not found: \(method ?? "<nil>")"))
        } else {
            log("ignoring unknown notification: \(method ?? "<nil>")")
        }
    }
}

// MARK: - Main loop

log("started (data file: \(AppPaths.tasksFile.path))")

while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }
    guard let data = trimmed.data(using: .utf8) else { continue }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        log("non-JSON input: \(trimmed.prefix(160))")
        writeMessage(errorResponse(id: nil, code: -32700, message: "Parse error"))
        continue
    }
    handle(obj)
}

log("stdin closed; exiting")
