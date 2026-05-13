import SwiftUI
import AppKit
import TodoItCore

enum TaskSection: String, CaseIterable, Identifiable {
    case today
    case upcoming
    case all
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .all: return "All Active"
        case .completed: return "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max.fill"
        case .upcoming: return "calendar"
        case .all: return "tray.full"
        case .completed: return "checkmark.circle"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var store: TaskStore
    @State private var selection: TaskSection = .today
    @State private var showingAdd: Bool = false
    @State private var editingTask: TodoTask?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("TodoIt")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            if selection == .completed && !store.completed.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button {
                        store.clearCompleted()
                    } label: {
                        Label("Clear Completed", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            TaskEditorView(mode: .create) { newTask in
                store.add(newTask)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(mode: .edit(task)) { updated in
                store.update(updated)
            }
        }
    }

    private var subtitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    private var sidebar: some View {
        List(TaskSection.allCases, selection: $selection) { section in
            HStack {
                Label(section.label, systemImage: section.systemImage)
                Spacer()
                let count = countFor(section)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .tag(section)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private var detail: some View {
        let tasks = filteredTasks
        if tasks.isEmpty {
            emptyState
                .frame(minWidth: 480)
        } else {
            List {
                ForEach(groupedTasks(tasks), id: \.0) { groupTitle, groupColor, items in
                    Section {
                        ForEach(items) { task in
                            TaskRow(task: task) { editingTask = task }
                                .environmentObject(store)
                        }
                    } header: {
                        HStack {
                            Text(groupTitle)
                                .font(.headline)
                                .foregroundStyle(groupColor)
                            Spacer()
                            Text("\(items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 480)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selection.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(emptySubtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if selection != .completed {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch selection {
        case .today: return "Nothing on your plate today"
        case .upcoming: return "No upcoming tasks"
        case .all: return "No active tasks"
        case .completed: return "Nothing completed yet"
        }
    }

    private var emptySubtitle: String {
        switch selection {
        case .today: return "Add one below, or schedule something for later."
        case .upcoming: return "Schedule a task for a future date."
        case .all: return "Add your first task to get started."
        case .completed: return "Knock something off your list — they'll show up here."
        }
    }

    private func countFor(_ section: TaskSection) -> Int {
        switch section {
        case .today: return store.todayAndOverdue.count
        case .upcoming: return store.upcoming.count
        case .all: return store.activeAll.count
        case .completed: return store.completed.count
        }
    }

    private var filteredTasks: [TodoTask] {
        switch selection {
        case .today: return store.todayAndOverdue
        case .upcoming: return store.upcoming
        case .all: return store.activeAll
        case .completed: return store.completed
        }
    }

    private func groupedTasks(_ tasks: [TodoTask]) -> [(String, Color, [TodoTask])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"

        if selection == .completed {
            return [("Completed", .secondary, tasks)]
        }

        let groups = Dictionary(grouping: tasks) { task -> Date in task.scheduledDate }
        return groups
            .map { (date, items) -> (Date, String, Color, [TodoTask]) in
                let label: String
                let color: Color
                if date < today {
                    label = "Overdue · \(dayFormatter.string(from: date))"
                    color = .red
                } else if date == today {
                    label = "Today"
                    color = .primary
                } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), date == tomorrow {
                    label = "Tomorrow"
                    color = .primary
                } else {
                    label = dayFormatter.string(from: date)
                    color = .primary
                }
                return (date, label, color, items)
            }
            .sorted { $0.0 < $1.0 }
            .map { ($0.1, $0.2, $0.3) }
    }
}

struct TaskRow: View {
    @EnvironmentObject var store: TaskStore
    let task: TodoTask
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.toggleComplete(task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack(spacing: 10) {
                    if task.priority == .high {
                        Label("High", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    } else if task.priority == .low {
                        Label("Low", systemImage: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                    if task.isCompleted, let completedAt = task.completedAt {
                        Text("Done \(relative(completedAt))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu {
            Button("Edit…") { onEdit() }
            Button(task.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                store.toggleComplete(task.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.remove(task.id)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

enum TaskEditorMode {
    case create
    case edit(TodoTask)
}

struct TaskEditorView: View {
    @Environment(\.dismiss) var dismiss
    let mode: TaskEditorMode
    let onSave: (TodoTask) -> Void

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Calendar.current.startOfDay(for: Date())
    @State private var priority: Priority = .normal

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEdit ? "Edit Task" : "New Task")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("What needs doing?", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 70, maxHeight: 110)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled Date").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                    HStack(spacing: 6) {
                        Button("Today") { date = Calendar.current.startOfDay(for: Date()) }
                        Button("Tomorrow") {
                            if let d = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) {
                                date = d
                            }
                        }
                        Button("+1 Week") {
                            if let d = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date())) {
                                date = d
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            Spacer(minLength: 4)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(isEdit ? "Save" : "Add Task") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500, height: 430)
        .onAppear {
            if case .edit(let task) = mode {
                title = task.title
                notes = task.notes ?? ""
                date = task.scheduledDate
                priority = task.priority
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create:
            let t = TodoTask(
                title: trimmedTitle,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                scheduledDate: date,
                priority: priority
            )
            onSave(t)
        case .edit(var task):
            task.title = trimmedTitle
            task.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            task.scheduledDate = Calendar.current.startOfDay(for: date)
            task.priority = priority
            onSave(task)
        }
        dismiss()
    }
}
