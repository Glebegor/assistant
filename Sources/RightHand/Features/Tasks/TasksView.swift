import AppKit
import SwiftUI

/// Tasks tab: open tasks from Notion, overdue and high priority first. Tick one to mark it done.
struct TasksView: View {
    let store: TaskStore
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            if !store.isConfigured {
                notConnected
            } else if store.tasks.isEmpty {
                if store.isLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PlaceholderView(systemImage: "checkmark.circle", title: L("Nothing to do"),
                                    message: "No open tasks for you in Notion.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.tasks) { task in
                            TaskRow(task: task, isCompleting: store.completing.contains(task.id)) { store.complete(task) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { if store.isConfigured { store.refreshIfStale() } }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("Tasks").font(.headline)
            if !store.tasks.isEmpty {
                let overdue = store.tasks.filter { $0.isOverdue() }.count
                Text(verbatim: "\(store.tasks.count)").foregroundStyle(.secondary)
                if overdue > 0 {
                    Text(L("%lld overdue", overdue))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.red.opacity(0.35), in: Capsule())
                }
            }
            Spacer()
            if store.isConfigured {
                Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
                    .buttonStyle(.notchPill())
                    .labelStyle(.iconOnly)
                    .disabled(store.isLoading)
                    .help("Load tasks from Notion again")
            }
        }
    }

    private var notConnected: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Connect Notion to see your tasks").font(.headline)
            Text("Add your Notion integration and choose task databases in Settings → Tasks.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.notchPill(prominent: true, tint: .white))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isCompleting: Bool
    let complete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: complete) {
                Image(systemName: isCompleting ? "checkmark.circle.fill" : (isHovered ? "checkmark.circle" : "circle"))
                    .font(.system(size: 15))
                    .foregroundStyle(isCompleting ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!task.canComplete)
            .help(task.canComplete ? "Mark as done" : "This database has no status or checkbox to mark it done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .lineLimit(2)
                    .strikethrough(isCompleting)
                    .foregroundStyle(isCompleting ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let due = task.due { dueBadge(due) }
                    if task.priorityLevel == .high, let name = task.priorityName {
                        Label(name, systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(verbatim: task.databaseName).foregroundStyle(.tertiary)
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered, let url = task.url {
                Button("Open in Notion", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open in Notion")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? .white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { if let url = task.url { NSWorkspace.shared.open(url) } }
    }

    @ViewBuilder
    private func dueBadge(_ due: Date) -> some View {
        let date = task.dueHasTime ? due.formatted(.dateTime.day().month(.abbreviated).hour().minute())
                                   : due.formatted(.dateTime.day().month(.abbreviated))
        if task.isOverdue() {
            Label(L("Overdue · %@", date), systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        } else if task.isDueToday() {
            Label(task.dueHasTime ? L("Today %@", due.formatted(.dateTime.hour().minute())) : L("Today"), systemImage: "calendar")
                .foregroundStyle(.yellow)
        } else {
            Label(date, systemImage: "calendar").foregroundStyle(.secondary)
        }
    }
}
