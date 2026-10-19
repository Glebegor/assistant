import AppKit
import SwiftUI

/// Settings → Tasks: Notion workspaces, their task databases, and who you are in each.
struct TasksSettingsPane: View {
    let store: TaskStore
    @State private var connections = TasksSettings.connections
    @State private var token = ""
    @State private var isConnecting = false
    @State private var message: String?

    var body: some View {
        Form {
            ForEach($connections) { $connection in
                Section {
                    ForEach(connection.databases) { database in
                        Toggle(isOn: Binding(
                            get: { connection.enabledDatabaseIDs.contains(database.id) },
                            set: { on in
                                if on { connection.enabledDatabaseIDs.insert(database.id) } else { connection.enabledDatabaseIDs.remove(database.id) }
                            }
                        )) {
                            Label(database.fullName, systemImage: "tablecells")
                        }
                    }
                    if connection.databases.isEmpty {
                        Text("No databases found. In Notion, open a task database → ••• → Connections → add your integration, then press Reload.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !connection.people.isEmpty {
                        Picker(selection: $connection.meID) {
                            Text("Anyone (show all tasks)").tag(String?.none)
                            ForEach(connection.people) { Text(verbatim: $0.name).tag(String?.some($0.id)) }
                        } label: {
                            SettingsRowLabel("This is me", subtitle: L("Tasks assigned to others are hidden"),
                                             systemImage: "person.fill", color: .blue)
                        }
                    }
                    HStack {
                        Button("Reload Databases") { Task { await reload(connection.id) } }
                        Spacer()
                        Button("Disconnect", role: .destructive) { disconnect(connection) }
                    }
                } header: {
                    Label(connection.workspaceName, systemImage: "n.square.fill")
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        SecureField("Token", text: $token, prompt: Text(verbatim: "ntn_…"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 170)
                            .onSubmit { Task { await connect() } }
                        Button("Connect") { Task { await connect() } }
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                    }
                } label: {
                    SettingsRowLabel(connections.isEmpty ? "Connect Notion" : "Add another workspace",
                                     subtitle: L("Integration token from %@", TasksSettings.integrationsURL.host() ?? ""),
                                     systemImage: "key.fill", color: .gray)
                        .onTapGesture { NSWorkspace.shared.open(TasksSettings.integrationsURL) }
                        .help("Open \(TasksSettings.integrationsURL.absoluteString)")
                }
                if isConnecting { ProgressView().controlSize(.small) }
                if let message { Text(message).font(.callout).foregroundStyle(.orange) }
            } header: {
                Text("Notion")
            } footer: {
                SettingsFooter("1. At notion.so/profile/integrations create an internal integration and copy its secret. 2. In Notion open each task database → ••• → Connections and add the integration. 3. Paste the secret here. The token stays in your Mac's Keychain. The Tasks tab shows open tasks assigned to you or to nobody, overdue and high-priority ones first.")
            }
        }
        .formStyle(.grouped)
        // Databases connected in Notion after setup show up without pressing Reload.
        .task {
            for connection in connections { await reload(connection.id) }
        }
        .onChange(of: connections) { _, connections in
            TasksSettings.connections = connections
            store.refresh()
        }
    }

    private func connect() async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isConnecting = true
        message = nil
        defer { isConnecting = false }
        let client = NotionClient(token: token)
        do {
            var connection = NotionConnection(workspaceName: try await client.workspaceName())
            Keychain.save(token, for: connection.keychainAccount)
            try await load(into: &connection, client: client, isNew: true)
            connections.append(connection)
            self.token = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func reload(_ id: UUID) async {
        guard let index = connections.firstIndex(where: { $0.id == id }),
              let token = Keychain.read(connections[index].keychainAccount) else { return }
        var connection = connections[index]
        do {
            try await load(into: &connection, client: NotionClient(token: token), isNew: false)
            connections[index] = connection
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    /// Reads the databases and people; new task databases are switched on.
    private func load(into connection: inout NotionConnection, client: NotionClient, isNew: Bool) async throws {
        let known = Set(connection.databases.map(\.id))
        connection.databases = try await client.databases().sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        for database in connection.databases where !known.contains(database.id) {
            let name = database.title.lowercased()
            let isArchive = ["archive", "archiv", "архив", "архів"].contains(where: name.contains)
            if !isArchive, ["task", "todo", "to-do", "задач", "завдан", "úkol"].contains(where: name.contains) {
                connection.enabledDatabaseIDs.insert(database.id)
            }
        }
        connection.enabledDatabaseIDs.formIntersection(connection.databases.map(\.id))
        connection.people = (try? await client.people()) ?? connection.people
        if connection.meID == nil, isNew, connection.people.count == 1 { connection.meID = connection.people[0].id }
    }

    private func disconnect(_ connection: NotionConnection) {
        Keychain.delete(connection.keychainAccount)
        connections.removeAll { $0.id == connection.id }
    }
}
