import Foundation

// Reads newly appended entries from a session transcript so the notch can
// mirror what the CLI is doing (latest tool call or streamed text) during
// the gaps between hook events. Claude Code keys entries by "type", Cursor
// by "role" — the message payloads share the same content-block shape.
enum TranscriptTailer {
    // Reading is capped so a huge burst of appended output stays cheap
    private static let maxRead: UInt64 = 524_288

    private static func entryKind(_ json: [String: Any]) -> String? {
        (json["type"] as? String) ?? (json["role"] as? String)
    }

    static func fileSize(_ path: String) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
    }

    // Returns the most recent displayable activity found after `offset`, plus
    // the offset of the last fully written line, or nil if nothing new
    static func newActivity(path: String, from offset: UInt64) -> (text: String, offset: UInt64)? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        guard size > offset else { return nil }
        let start = size - offset > maxRead ? size - maxRead : offset
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        // Only consume complete lines — the CLI may be mid-append
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return nil }
        let complete = data[data.startIndex...lastNewline]
        let consumed = start + UInt64(complete.count)
        guard let text = String(data: complete, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard
                let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                entryKind(json) == "assistant",
                let message = json["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { continue }

            for block in content.reversed() {
                switch block["type"] as? String {
                case "tool_use":
                    if let name = block["name"] as? String {
                        return (toolLabel(name: name, input: block["input"] as? [String: Any]), consumed)
                    }
                case "text":
                    if let snippet = firstLine(block["text"] as? String) {
                        return (snippet, consumed)
                    }
                default:
                    continue
                }
            }
        }
        return nil
    }

    // Full text of the final assistant reply — the contiguous run of text
    // blocks after the last tool call or user message. Shown in the notch
    // when a session finishes.
    static func finalResponse(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > maxRead ? size - maxRead : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var current: [String] = []
        for line in text.split(separator: "\n") {
            guard
                let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let type = entryKind(json)
            else { continue }

            if type == "user" {
                current = []
                continue
            }
            guard type == "assistant",
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }

            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let blockText = block["text"] as? String,
                       !blockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        current.append(blockText)
                    }
                case "tool_use":
                    current = []
                default:
                    break
                }
            }
        }

        let joined = current.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return joined.count > 6000 ? String(joined.prefix(6000)) + "…" : joined
    }

    // Claude Code appends custom-title entries as the session title is set
    // or renamed (newest wins); continued sessions instead carry summary
    // entries near the head of the file
    static func sessionTitle(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0

        let tailStart = size > maxRead ? size - maxRead : 0
        try? handle.seek(toOffset: tailStart)
        if let data = try? handle.readToEnd(),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n").reversed() {
                guard
                    let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    json["type"] as? String == "custom-title",
                    let title = json["customTitle"] as? String, !title.isEmpty
                else { continue }
                return title
            }
        }

        try? handle.seek(toOffset: 0)
        guard let data = try? handle.read(upToCount: 131_072),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var title: String?
        for line in text.split(separator: "\n") {
            guard
                let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                json["type"] as? String == "summary",
                let summary = json["summary"] as? String, !summary.isEmpty
            else { continue }
            title = summary
        }
        return title
    }

    // "Read NotchView.swift", "Bash swift build" — tool name plus the most
    // salient argument, so the notch shows what the agent is doing right now
    private static func toolLabel(name: String, input: [String: Any]?) -> String {
        var display = name
        if name.hasPrefix("mcp__") {
            let parts = name.components(separatedBy: "__")
            display = parts.last ?? name
        }
        guard let input else { return display }

        for key in ["file_path", "path", "notebook_path"] {
            if let path = input[key] as? String, !path.isEmpty {
                return display + " " + (path as NSString).lastPathComponent
            }
        }
        for key in ["command", "pattern", "glob_pattern", "query", "search_term", "url", "description", "skill", "prompt"] {
            if let value = firstLine(input[key] as? String) {
                return display + " " + value
            }
        }
        return display
    }

    private static func firstLine(_ text: String?) -> String? {
        guard let text else { return nil }
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
