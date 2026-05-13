import SwiftUI
import AppKit
import TodoItCore

struct MenuBarView: View {
    @EnvironmentObject var store: TaskStore
    @State private var newTaskTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            taskList
            Divider()
            quickAddRow
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TodoIt")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let count = store.todayAndOverdue.count
            Text(count == 0 ? "All clear" : "\(count) open")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerSubtitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let tasks = store.todayAndOverdue
                if tasks.isEmpty {
                    emptyView
                } else {
                    ForEach(tasks) { task in
                        MenuBarTaskRow(task: task)
                        if task.id != tasks.last?.id {
                            Divider().padding(.leading, 38)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 160, maxHeight: 360)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Nothing on your plate")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add a task below or open TodoIt")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var quickAddRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Add task for today…", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .onSubmit(addTask)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                AppDelegate.shared?.showMainWindow()
            } label: {
                Label("Open TodoIt", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("o", modifiers: [.command])

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.callout)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.add(TodoTask(title: title))
        newTaskTitle = ""
    }
}

struct MenuBarTaskRow: View {
    @EnvironmentObject var store: TaskStore
    let task: TodoTask
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleComplete(task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                if isOverdue {
                    Text("Overdue · \(formattedDate)")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if task.priority == .high {
                    Text("High priority")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)

            if hovering {
                Button {
                    store.remove(task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { hovering = $0 }
    }

    private var isOverdue: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return !task.isCompleted && task.scheduledDate < today
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: task.scheduledDate)
    }
}
