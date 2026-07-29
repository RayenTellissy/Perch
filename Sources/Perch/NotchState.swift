import Foundation

final class NotchState: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var sessions: [AgentSession] = []
    @Published var approvals: [ApprovalRequest] = []
    @Published var questions: [QuestionRequest] = []
    @Published var usage: UsageSnapshot?
    @Published var showNewSession = false {
        didSet { updateExpansion() }
    }
    @Published private(set) var recentDirectories: [String] =
        UserDefaults.standard.stringArray(forKey: "recentDirectories") ?? []
    // Session whose finished response is being shown front and center —
    // set on Stop, pins the island open until dismissed or timed out
    @Published private(set) var spotlightSessionID: String?

    var spotlightSession: AgentSession? {
        spotlightSessionID.flatMap { id in sessions.first { $0.id == id } }
    }

    private var spotlightDismissTask: DispatchWorkItem?

    var isHovering = false {
        didSet { updateExpansion() }
    }

    private var hoverExitTask: DispatchWorkItem?

    // Expand immediately, collapse only after a grace period — the resize
    // animation shifts the hover boundary under the cursor, and reacting to
    // every exit event makes the panel flicker
    func setHovering(_ hovering: Bool) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        if hovering {
            isHovering = true
        } else {
            let task = DispatchWorkItem { [weak self] in
                self?.isHovering = false
            }
            hoverExitTask = task
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Prefs.shared.hoverCollapseDelay,
                execute: task
            )
        }
    }

    // Collapse immediately, skipping the hover grace period — used when the
    // settings window opens so the island doesn't float above it
    func collapseNow() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        isHovering = false
    }

    var onApprovalDecision: ((String, Bool) -> Void)?
    var onApprovalAlways: ((String) -> Void)?
    var onQuestionAnswered: ((String, [(question: String, answers: [String])]) -> Void)?
    var onOpenSettings: (() -> Void)?

    func addQuestion(_ request: QuestionRequest) {
        questions.append(request)
        SoundPlayer.shared.play(.question)
        if let index = sessions.firstIndex(where: { $0.id == request.sessionID }) {
            sessions[index].status = .waitingForAnswer
        }
        updateExpansion()
    }

    func removeQuestion(_ id: String) {
        questions.removeAll { $0.id == id }
        if let index = sessions.firstIndex(where: { $0.status == .waitingForAnswer }),
           !questions.contains(where: { $0.sessionID == sessions[index].id }) {
            sessions[index].status = .working
        }
        updateExpansion()
    }

    func addApproval(_ request: ApprovalRequest) {
        approvals.append(request)
        SoundPlayer.shared.play(.approval)
        if let index = sessions.firstIndex(where: { $0.id == request.sessionID }) {
            sessions[index].status = .waitingForApproval
        }
        updateExpansion()
    }

    func removeApproval(_ id: String) {
        approvals.removeAll { $0.id == id }
        if let index = sessions.firstIndex(where: { $0.status == .waitingForApproval }),
           !approvals.contains(where: { $0.sessionID == sessions[index].id }) {
            sessions[index].status = .working
        }
        updateExpansion()
    }

    private func updateExpansion() {
        // Picking a project pins the panel open even if the cursor drifts
        // off the island
        let expanded = isHovering || !approvals.isEmpty || !questions.isEmpty
            || showNewSession || spotlightSessionID != nil
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded {
            UsageTracker.shared.refreshIfStale { [weak self] snapshot in
                self?.usage = snapshot
            }
        }
    }

    // Gemini CLI event names mapped onto the shared vocabulary
    private static let eventAliases = [
        "BeforeTool": "PreToolUse",
        "AfterTool": "PostToolUse",
        "AfterAgent": "Stop"
    ]

    private static let agentNames = [
        "claude": "Claude Code",
        "codex": "Codex",
        "gemini": "Gemini",
        "opencode": "OpenCode",
        "cursor": "Cursor"
    ]

    func apply(event: [String: Any]) {
        var event = event
        if (event["fv_agent"] as? String) == "cursor" {
            guard let normalized = Self.normalizeCursorEvent(event) else { return }
            event = normalized
        }
        guard
            let rawName = event["hook_event_name"] as? String,
            let sessionID = event["session_id"] as? String
        else { return }

        let name = Self.eventAliases[rawName] ?? rawName
        let agent = (event["fv_agent"] as? String) ?? "claude"

        DispatchQueue.main.async {
            self.handle(name: name, sessionID: "\(agent):\(sessionID)", event: event)
        }
    }

    // Cursor hooks use their own event names and payload shapes — rebuild
    // each event in the shared vocabulary before the generic handling. The
    // fv_* enrichment and transcript_path pass through untouched (Cursor
    // transcripts are close enough to Claude's for the tailer to read).
    private static func normalizeCursorEvent(_ event: [String: Any]) -> [String: Any]? {
        guard
            let name = event["hook_event_name"] as? String,
            let conversationID = event["conversation_id"] as? String
        else { return nil }

        var out = event
        out["session_id"] = conversationID
        if out["cwd"] == nil,
           let roots = event["workspace_roots"] as? [String], let root = roots.first {
            out["cwd"] = root
        }

        switch name {
        case "beforeSubmitPrompt":
            out["hook_event_name"] = "UserPromptSubmit"
        case "beforeShellExecution":
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = "Bash"
            out["tool_input"] = ["command": (event["command"] as? String) ?? ""]
        case "afterShellExecution":
            out["hook_event_name"] = "PostToolUse"
            out["tool_name"] = "Bash"
        case "beforeMCPExecution":
            out["hook_event_name"] = "PreToolUse"
            // tool_input arrives as a JSON string
            if let text = event["tool_input"] as? String,
               let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                out["tool_input"] = parsed
            }
        case "afterMCPExecution":
            out["hook_event_name"] = "PostToolUse"
        case "afterFileEdit":
            // Fires after the write, but as live status "Editing X" reads best
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = "Edit"
            out["tool_input"] = ["file_path": (event["file_path"] as? String) ?? ""]
        case "stop":
            out["hook_event_name"] = "Stop"
        default:
            return nil
        }
        return out
    }

    private func handle(name: String, sessionID: String, event: [String: Any]) {
        switch name {
        case "SessionStart":
            upsert(sessionID, event: event) { session in
                session.status = .idle
                session.lastActivity = "Session started"
            }
        case "UserPromptSubmit":
            if spotlightSessionID == sessionID { dismissSpotlight() }
            upsert(sessionID, event: event) { session in
                session.status = .working
                if let prompt = event["prompt"] as? String {
                    session.lastActivity = Self.truncate(prompt)
                    session.lastPrompt = Self.truncate(prompt, to: 90)
                }
                session.narration = ""
                session.lastResponse = ""
                session.toolName = ""
                session.toolDetail = ""
                Self.beginStreaming(&session)
            }
        case "PreToolUse":
            upsert(sessionID, event: event) { session in
                session.status = .working
                session.lastActivity = Self.describeTool(event)
                session.toolName = Self.toolDisplayName(event)
                session.toolDetail = Self.toolArgument(event)
            }
        case "PostToolUse":
            upsert(sessionID, event: event) { session in
                session.status = .working
                session.lastActivity = "Thinking…"
                if !session.isStreaming {
                    // App joined mid-turn — catch up from the transcript tail
                    Self.beginStreaming(&session, catchUp: true)
                }
            }
        case "Notification":
            upsert(sessionID, event: event) { session in
                let message = (event["message"] as? String) ?? ""
                if message.localizedCaseInsensitiveContains("permission") {
                    session.status = .waitingForApproval
                } else {
                    session.status = .waitingForAnswer
                }
                session.lastActivity = Self.truncate(message)
            }
        case "Stop":
            upsert(sessionID, event: event) { session in
                session.status = .done
                session.lastActivity = "Finished"
                session.narration = ""
                session.isStreaming = false
                session.toolName = ""
                session.toolDetail = ""
            }
            SoundPlayer.shared.play(.done)
            showSpotlight(for: sessionID)
        case "SessionEnd":
            if spotlightSessionID == sessionID { dismissSpotlight() }
            sessions.removeAll { $0.id == sessionID }
        default:
            break
        }
        fetchTitleIfNeeded(sessionID)
        updateTranscriptPolling()
    }

    // MARK: - Response spotlight
    //
    // When a session finishes, the island pops open on its own and shows the
    // full final response, then quietly folds back after a grace period

    private func showSpotlight(for sessionID: String) {
        guard Prefs.shared.spotlightEnabled,
              let session = sessions.first(where: { $0.id == sessionID }),
              session.transcriptPath != nil else { return }
        spotlightSessionID = sessionID
        updateExpansion()
        scheduleSpotlightDismiss(after: Prefs.shared.spotlightDuration)
        fetchFinalResponse(sessionID: sessionID)
    }

    func dismissSpotlight() {
        spotlightDismissTask?.cancel()
        spotlightDismissTask = nil
        spotlightSessionID = nil
        updateExpansion()
    }

    private func scheduleSpotlightDismiss(after seconds: TimeInterval = 30) {
        spotlightDismissTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Reading it — keep it up and check back later
            if self.isHovering {
                self.scheduleSpotlightDismiss(after: 10)
            } else {
                self.dismissSpotlight()
            }
        }
        spotlightDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }

    // The Stop hook can fire moments before the CLI flushes the last
    // transcript lines, so retry briefly if the reply isn't there yet
    private func fetchFinalResponse(sessionID: String, attempt: Int = 0) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let path = session.transcriptPath else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let response = TranscriptTailer.finalResponse(path: path)
            DispatchQueue.main.async {
                guard let self else { return }
                if let response {
                    guard let index = self.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                    self.sessions[index].lastResponse = response
                } else if attempt < 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self.fetchFinalResponse(sessionID: sessionID, attempt: attempt + 1)
                    }
                }
            }
        }
    }

    // Titles are written to the transcript a few turns in and can be
    // renamed later, so keep checking — throttled per session
    private var titleFetchedAt: [String: Date] = [:]

    private func fetchTitleIfNeeded(_ sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }),
              let path = session.transcriptPath
        else { return }
        if let last = titleFetchedAt[sessionID], Date().timeIntervalSince(last) < 15 { return }
        titleFetchedAt[sessionID] = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let title = TranscriptTailer.sessionTitle(path: path) else { return }
            DispatchQueue.main.async {
                guard let self,
                      let index = self.sessions.firstIndex(where: { $0.id == sessionID })
                else { return }
                self.sessions[index].title = title
            }
        }
    }

    // MARK: - Transcript tailing
    //
    // Hooks only fire around tool calls, so while the model is thinking or
    // writing text the notch would show a static placeholder. Tailing the
    // session transcript fills that gap with what the CLI is actually showing.

    private var transcriptTimer: Timer?

    private static func beginStreaming(_ session: inout AgentSession, catchUp: Bool = false) {
        guard let path = session.transcriptPath else { return }
        session.isStreaming = true
        session.transcriptOffset = catchUp ? 0 : TranscriptTailer.fileSize(path)
    }

    private func updateTranscriptPolling() {
        let needed = sessions.contains { $0.isStreaming && $0.status == .working }
        if needed, transcriptTimer == nil {
            transcriptTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.pollTranscripts()
            }
        } else if !needed, let timer = transcriptTimer {
            timer.invalidate()
            transcriptTimer = nil
        }
    }

    private func pollTranscripts() {
        for session in sessions where session.isStreaming && session.status == .working {
            guard let path = session.transcriptPath else { continue }
            let id = session.id
            let offset = session.transcriptOffset
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let update = TranscriptTailer.newActivity(path: path, from: offset) else { return }
                DispatchQueue.main.async {
                    guard let self,
                          let index = self.sessions.firstIndex(where: { $0.id == id }),
                          self.sessions[index].isStreaming,
                          self.sessions[index].status == .working
                    else { return }
                    self.sessions[index].narration = Self.truncate(update.text)
                    self.sessions[index].transcriptOffset = update.offset
                    self.sessions[index].lastUpdated = Date()
                }
            }
        }
        updateTranscriptPolling()
    }

    private func upsert(_ sessionID: String, event: [String: Any], update: (inout AgentSession) -> Void) {
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            applyLocation(event, to: &sessions[index])
            update(&sessions[index])
            sessions[index].lastUpdated = Date()
        } else {
            let agent = (event["fv_agent"] as? String) ?? "claude"
            var session = AgentSession(
                id: sessionID,
                agentName: Self.agentNames[agent] ?? agent.capitalized,
                directory: Self.abbreviate(event["cwd"] as? String ?? ""),
                status: .idle,
                lastActivity: ""
            )
            applyLocation(event, to: &session)
            update(&session)
            sessions.append(session)
        }
    }

    private func applyLocation(_ event: [String: Any], to session: inout AgentSession) {
        if let path = event["transcript_path"] as? String { session.transcriptPath = path }
        // Agents without a transcript file (OpenCode) send the title inline
        if let title = event["fv_title"] as? String, !title.isEmpty { session.title = title }
        if let tty = event["fv_tty"] as? String { session.tty = tty }
        if let pid = event["fv_term_pid"] as? Int { session.terminalAppPID = Int32(pid) }
        if let path = event["fv_term_path"] as? String { session.terminalAppPath = path }
        if let pane = event["fv_tmux_pane"] as? String { session.tmuxPane = pane }
        if let pid = event["fv_agent_pid"] as? Int { session.agentPID = Int32(pid) }
        if let path = event["fv_agent_path"] as? String { session.agentPath = path }
        if let cwd = event["cwd"] as? String, !cwd.isEmpty {
            session.cwd = cwd
            recordDirectory(cwd)
        }
    }

    private func recordDirectory(_ path: String) {
        guard recentDirectories.first != path else { return }
        var dirs = recentDirectories.filter { $0 != path }
        dirs.insert(path, at: 0)
        recentDirectories = Array(dirs.prefix(Prefs.shared.recentDirectoryLimit))
        UserDefaults.standard.set(recentDirectories, forKey: "recentDirectories")
    }

    private static func describeTool(_ event: [String: Any]) -> String {
        let tool = (event["tool_name"] as? String) ?? "Tool"
        let input = event["tool_input"] as? [String: Any]
        let file = (input?["file_path"] as? String).map { ($0 as NSString).lastPathComponent }

        let text: String
        switch tool {
        case "Bash":
            text = "Running: \((input?["command"] as? String) ?? "command")"
        case "Write":
            text = "Creating \(file ?? "a file")"
        case "Edit", "MultiEdit":
            text = "Editing \(file ?? "a file")"
        case "NotebookEdit":
            text = "Editing \(file ?? "a notebook")"
        case "Read":
            text = "Reading \(file ?? "a file")"
        case "Grep":
            text = "Searching for \((input?["pattern"] as? String) ?? "…")"
        case "Glob":
            text = "Finding files: \((input?["pattern"] as? String) ?? "…")"
        case "Task", "Agent":
            text = "Spawning agent: \((input?["description"] as? String) ?? "…")"
        case "WebSearch":
            text = "Searching web: \((input?["query"] as? String) ?? "…")"
        case "WebFetch":
            let host = (input?["url"] as? String).flatMap { URL(string: $0)?.host } ?? "a page"
            text = "Fetching \(host)"
        case "TodoWrite", "TaskCreate", "TaskUpdate":
            text = "Updating task list"
        case "AskUserQuestion":
            text = "Asking a question"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
                text = "Using \(parts.count > 1 ? parts[1] : "MCP"): \(parts.last ?? "tool")"
            } else {
                text = "Using \(tool)"
            }
        }
        return truncate(text)
    }

    private static func toolDisplayName(_ event: [String: Any]) -> String {
        let tool = (event["tool_name"] as? String) ?? "Tool"
        guard tool.hasPrefix("mcp__") else { return tool }
        let parts = tool.split(separator: "_", omittingEmptySubsequences: true)
        return parts.count > 1 ? String(parts[1]) : "MCP"
    }

    private static func toolArgument(_ event: [String: Any]) -> String {
        let tool = (event["tool_name"] as? String) ?? ""
        let input = event["tool_input"] as? [String: Any]
        let file = (input?["file_path"] as? String).map { ($0 as NSString).lastPathComponent }

        let text: String
        switch tool {
        case "Bash":
            text = (input?["command"] as? String) ?? ""
        case "Write", "Edit", "MultiEdit", "NotebookEdit", "Read":
            text = file ?? ""
        case "Grep", "Glob":
            text = (input?["pattern"] as? String) ?? ""
        case "Task", "Agent":
            text = (input?["description"] as? String) ?? ""
        case "WebSearch":
            text = (input?["query"] as? String) ?? ""
        case "WebFetch":
            text = (input?["url"] as? String).flatMap { URL(string: $0)?.host } ?? ""
        default:
            text = ""
        }
        return truncate(text, to: 60)
    }

    private static func truncate(_ text: String, to limit: Int = 70) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    private static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home)
            ? "~" + path.dropFirst(home.count)
            : path
    }
}

struct ApprovalRequest: Identifiable {
    let id: String
    let sessionID: String
    let toolName: String
    let detail: String
    var cwd: String = ""
    var alwaysAllowRule: String?
}

struct QuestionRequest: Identifiable {
    struct Option {
        let label: String
        let description: String
    }

    struct Question {
        let text: String
        let header: String
        let multiSelect: Bool
        let options: [Option]
    }

    let id: String
    let sessionID: String
    let questions: [Question]
}

struct AgentSession: Identifiable {
    enum Status: String {
        case working = "Working"
        case waitingForApproval = "Needs approval"
        case waitingForAnswer = "Has a question"
        case idle = "Idle"
        case done = "Done"
    }

    let id: String
    var agentName: String
    var directory: String
    var status: Status
    var lastActivity: String
    var lastUpdated = Date()
    var cwd: String = ""
    var tty: String?
    var terminalAppPID: Int32?
    var terminalAppPath: String?
    var tmuxPane: String?
    var agentPID: Int32?
    var agentPath: String?
    var transcriptPath: String?
    var transcriptOffset: UInt64 = 0
    var isStreaming = false
    // Latest assistant text or thinking from the transcript, shown alongside
    // the hook-driven tool activity
    var narration = ""
    // Session summary from the transcript when available, else the first
    // prompt — the row's headline next to the project name
    var title = ""
    var lastPrompt = ""
    // Full text of the final reply, filled in from the transcript on Stop
    var lastResponse = ""
    var toolName = ""
    var toolDetail = ""
}
