import Foundation

/// Online services the AI can use (Notion, ClickUp, Google), connected in Settings → Services.
enum Integrations {
    static func tools(access: FileAccess) -> [AssistantTool] {
        var tools: [AssistantTool] = []
        if NotionAccess.isConnected {
            tools += [NotionSearchTool(), NotionReadPageTool(), NotionQueryDatabaseTool(), NotionUpdateTaskTool()]
        }
        if JiraSettings.isConnected {
            tools += [JiraSearchTool(), JiraReadIssueTool()]
        }
        if Outlook.isConnected {
            tools += [OutlookSearchTool(), OutlookReadTool()]
        }
        if ClickUpSettings.isConnected {
            tools += [ClickUpFindTasksTool(), ClickUpReadTaskTool(), ClickUpUpdateTaskTool()]
        }
        if GoogleAuth.isConnected {
            tools += [GmailSearchTool(), GmailReadTool(), DriveSearchTool(), DriveReadTool(), DriveCreateDocTool(),
                      DriveUploadTool(access: access), DriveDownloadTool(access: access)]
        }
        return tools
    }

    static var catalog: [(name: String, displayName: String)] {
        [("notion_search", L("Search Notion")), ("notion_read_page", L("Read Notion pages")),
         ("notion_query_database", L("Read Notion databases")), ("notion_update_task", L("Change Notion tasks")),
         ("clickup_find_tasks", L("Search ClickUp tasks")), ("clickup_read_task", L("Read ClickUp tasks")),
         ("clickup_update_task", L("Change ClickUp tasks")),
         ("jira_search", L("Search Jira")), ("jira_read_issue", L("Read Jira issues")),
         ("outlook_search", L("Search Outlook mail")), ("outlook_read", L("Read Outlook mail")),
         ("gmail_search", L("Search Gmail")), ("gmail_read", L("Read emails")),
         ("drive_search", L("Search Google Drive")), ("drive_read", L("Read Google Drive files")),
         ("drive_create_doc", L("Create Google Docs")), ("drive_upload", L("Upload to Google Drive")),
         ("drive_download", L("Download from Google Drive"))]
    }

    /// Tells the AI which services it can use.
    static var systemPrompt: String? {
        var services = ["the user's RightHand notes (list, search and read; share a note as a Markdown link to its righthand:// link)"]
        if NotionAccess.isConnected { services.append("Notion (search, read pages and databases, change tasks)") }
        if ClickUpSettings.isConnected { services.append("ClickUp (find, read and change tasks)") }
        if JiraSettings.isConnected { services.append("Jira (search issues with words or JQL, read issues)") }
        if Outlook.isConnected { services.append("Outlook mail of \(Outlook.email ?? "the user") (search and read emails)") }
        if GoogleAuth.isConnected {
            services.append("Gmail of \(GoogleAuth.email ?? "the user") (search and read emails)")
            services.append("Google Drive (search, read, create Docs, upload, download)")
        }
        return """
        # Connected services

        You can use these services with your tools: \(services.joined(separator: "; ")). \
        When a question is about the user's tasks, emails or documents, look them up instead of guessing. \
        Today is \(Date().formatted(.iso8601.year().month().day())).
        """
    }

    /// Changes when a service is connected or disconnected.
    static var fingerprint: String {
        "\(NotionAccess.isConnected)\(ClickUpSettings.isConnected)\(GoogleAuth.isConnected)\(JiraSettings.isConnected)\(Outlook.isConnected)"
    }
}
