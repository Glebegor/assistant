import AppKit
import SwiftUI

/// An AI answer in Markdown: paragraphs, headings, lists, quotes, tables and code blocks (with
/// the language, light syntax colours and a Copy button). `compact` is for the notch.
struct MarkdownView: View {
    let text: String
    var compact = false

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodySize: CGFloat { compact ? 12.5 : 13.5 }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text, size: bodySize))
                .font(.system(size: bodySize))
                .lineSpacing(compact ? 1.5 : 2.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.inline(text, size: bodySize))
                .font(.system(size: bodySize + (level == 1 ? 5 : level == 2 ? 3 : 1.5), weight: .semibold))
                .padding(.top, compact ? 2 : 4)
                .textSelection(.enabled)
        case .list(let items):
            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Group {
                            if let number = item.number {
                                Text(verbatim: "\(number).").monospacedDigit()
                            } else if let checked = item.checked {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(checked ? Theme.neon : .secondary)
                            } else {
                                Circle().fill(Theme.neon.opacity(0.8)).frame(width: 4.5, height: 4.5)
                                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + bodySize * 0.32 }
                            }
                        }
                        .font(.system(size: bodySize))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 10, alignment: .trailing)
                        Text(Self.inline(item.text, size: bodySize))
                            .font(.system(size: bodySize))
                            .lineSpacing(1.5)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 14)
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                Capsule().fill(Theme.neon.opacity(0.6)).frame(width: 2.5)
                Text(Self.inline(text, size: bodySize))
                    .font(.system(size: bodySize))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code, compact: compact)
        case .table(let rows):
            TableBlockView(rows: rows, size: bodySize)
        case .rule:
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.vertical, 2)
        }
    }

    /// Bold, italics, links and `code` (monospaced on a faint background).
    static func inline(_ text: String, size: CGFloat) -> AttributedString {
        var string = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in string.runs where run.inlinePresentationIntent?.contains(.code) == true {
            string[run.range].font = .system(size: size * 0.92, design: .monospaced)
            string[run.range].foregroundColor = Color(red: 0.62, green: 0.82, blue: 1.0)
            string[run.range].backgroundColor = Color.white.opacity(0.08)
        }
        for run in string.runs where run.link != nil {
            string[run.range].foregroundColor = Theme.neon
            string[run.range].underlineStyle = .single
        }
        return string
    }
}

// MARK: Parsing

enum MarkdownBlock: Equatable {
    struct Item: Equatable {
        var text: String
        var number: Int?
        var checked: Bool?
        var indent: Int
    }

    case paragraph(String)
    case heading(Int, String)
    case list([Item])
    case quote(String)
    case code(language: String, code: String)
    case table([[String]])
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [Item] = []
        var quote: [String] = []
        var table: [[String]] = []
        var fence: (marker: String, language: String, lines: [String])?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !items.isEmpty { blocks.append(.list(items)); items = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            if !table.isEmpty {
                blocks.append(table.count >= 2 ? .table(table) : .paragraph(table.map { $0.joined(separator: " | ") }.joined(separator: "\n")))
                table = []
            }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Inside a code block everything is kept as it is.
            if var open = fence {
                if trimmed.hasPrefix(open.marker) && trimmed.drop { $0 == open.marker.first }.trimmingCharacters(in: .whitespaces).isEmpty {
                    blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let marker = String(trimmed.prefix(3))
                fence = (marker, trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased(), [])
                continue
            }
            if trimmed.isEmpty { flush(); continue }

            if let heading = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"),
               trimmed[heading] == " ", trimmed.distance(from: trimmed.startIndex, to: heading) <= 6 {
                flush()
                blocks.append(.heading(trimmed.distance(from: trimmed.startIndex, to: heading), String(trimmed[heading...]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) && paragraph.isEmpty {
                flush()
                blocks.append(.rule)
                continue
            }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1 {
                if !paragraph.isEmpty || !items.isEmpty || !quote.isEmpty { flush() }
                let cells = trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // The |---|---| line under the header.
                if !cells.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } }) { table.append(cells) }
                continue
            }
            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty || !items.isEmpty || !table.isEmpty { flush() }
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if let item = listItem(line) {
                if !paragraph.isEmpty || !quote.isEmpty || !table.isEmpty { flush() }
                items.append(item)
                continue
            }
            // A wrapped line of the last list item.
            if !items.isEmpty, line.hasPrefix("  ") {
                items[items.count - 1].text += " " + trimmed
                continue
            }
            if !items.isEmpty || !quote.isEmpty || !table.isEmpty { flush() }
            paragraph.append(trimmed)
        }
        // An answer still streaming may end inside a code block.
        if let open = fence { blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func listItem(_ line: String) -> Item? {
        let spaces = line.prefix { $0 == " " || $0 == "\t" }.count
        let rest = line.dropFirst(spaces)
        let indent = min(3, spaces / 2)
        if let first = rest.first, "-*+•".contains(first), rest.dropFirst().first == " " {
            var text = String(rest.dropFirst(2))
            var checked: Bool?
            if text.hasPrefix("[ ] ") { checked = false; text.removeFirst(4) }
            else if text.lowercased().hasPrefix("[x] ") { checked = true; text.removeFirst(4) }
            return Item(text: text, checked: checked, indent: indent)
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3, let number = Int(digits) {
            let after = rest.dropFirst(digits.count)
            if let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " {
                return Item(text: String(after.dropFirst(2)), number: number, indent: indent)
            }
        }
        return nil
    }
}

// MARK: Code

/// A code block: language and Copy on top, the code below with light syntax colours.
private struct CodeBlockView: View {
    let language: String
    let code: String
    let compact: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Theme.neon.opacity(0.8)).frame(width: 5, height: 5)
                Text(verbatim: language.isEmpty ? "code" : language)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(copied ? Theme.neon : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))

            ScrollView(.horizontal) {
                Text(SyntaxHighlighter.highlight(code, language: language, size: compact ? 11.5 : 12.5))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .scrollIndicators(.automatic)
        }
        .background(Color(red: 0.03, green: 0.035, blue: 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Colours keywords, strings, comments and numbers. Not a parser: good enough to read code.
enum SyntaxHighlighter {
    private static let keywords: Set<String> = [
        // Swift, Kotlin, JS/TS, Python, Go, Rust, C-like, shell
        "func", "let", "var", "if", "else", "guard", "return", "for", "while", "in", "switch", "case", "default", "break",
        "continue", "struct", "class", "enum", "protocol", "extension", "import", "init", "self", "Self", "true", "false",
        "nil", "null", "undefined", "None", "True", "False", "try", "catch", "throw", "throws", "async", "await", "static",
        "private", "public", "internal", "fileprivate", "final", "override", "const", "function", "new", "this", "typeof",
        "interface", "type", "export", "from", "as", "def", "elif", "lambda", "pass", "with", "yield", "not", "and", "or",
        "is", "package", "fn", "mut", "impl", "pub", "use", "mod", "match", "where", "go", "defer", "chan", "map", "do",
        "then", "fi", "done", "echo", "int", "float", "double", "bool", "string", "void", "char", "long", "select",
        "insert", "update", "delete", "create", "table", "join", "on", "group", "order", "by", "val", "object", "when",
    ]

    static func highlight(_ code: String, language: String, size: CGFloat) -> AttributedString {
        var result = AttributedString(code)
        result.font = .system(size: size, design: .monospaced)
        result.foregroundColor = Color(white: 0.88)
        let ns = code as NSString
        let hashComments = ["python", "py", "sh", "bash", "zsh", "shell", "ruby", "rb", "yaml", "yml", "toml", "r", "perl", "make", "dockerfile"]
            .contains(language)
        let patterns: [(String, Color)] = [
            ("\\b\\d+(\\.\\d+)?\\b", Color(red: 0.85, green: 0.6, blue: 1.0)),
            ("\\b[A-Z][A-Za-z0-9_]*\\b", Color(red: 0.45, green: 0.85, blue: 0.85)),
            ("\\b[A-Za-z_][A-Za-z0-9_]*(?=\\()", Color(red: 0.55, green: 0.75, blue: 1.0)),
            ("\"(\\\\.|[^\"\\\\\\n])*\"|'(\\\\.|[^'\\\\\\n])*'|`[^`]*`", Color(red: 0.98, green: 0.62, blue: 0.45)),
            (hashComments ? "#[^\\n]*" : "//[^\\n]*|/\\*[\\s\\S]*?\\*/", Color(white: 0.45)),
        ]
        func apply(_ range: NSRange, _ color: Color) {
            guard let swiftRange = Range(range, in: code),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: result) else { return }
            result[lower..<upper].foregroundColor = color
        }
        // Keywords first; strings and comments last so they win.
        if let regex = try? NSRegularExpression(pattern: "\\b[A-Za-z_]+\\b") {
            for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length))
            where keywords.contains(ns.substring(with: match.range)) {
                apply(match.range, Color(red: 1.0, green: 0.45, blue: 0.62))
            }
        }
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                apply(match.range, color)
            }
        }
        return result
    }
}

// MARK: Tables

private struct TableBlockView: View {
    let rows: [[String]]
    let size: CGFloat

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            Text(MarkdownView.inline(column < row.count ? row[column] : "", size: size))
                                .font(.system(size: size - 0.5, weight: index == 0 ? .semibold : .regular))
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == 0 ? Color.white.opacity(0.06) : (index % 2 == 0 ? Color.white.opacity(0.02) : .clear))
                        }
                    }
                    if index < rows.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .fixedSize()
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .scrollIndicators(.never)
    }
}
