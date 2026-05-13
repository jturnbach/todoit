import SwiftUI
import AppKit
import TodoItCore

@main
struct TodoItApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: TaskStore

    var body: some View {
        let count = store.todayAndOverdue.count
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium))
            }
        } else {
            Image(systemName: "checklist")
        }
    }
}
