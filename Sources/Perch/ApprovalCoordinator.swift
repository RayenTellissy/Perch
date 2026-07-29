import Foundation

final class ApprovalCoordinator {
    static let clickTimeout: TimeInterval = 45
    static let questionTimeout: TimeInterval = 45

    private let state: NotchState
    private var pending: [String: ([String: Any]) -> Void] = [:]

    init(state: NotchState) {
        self.state = state
        state.onApprovalDecision = { [weak self] id, allowed in
            self?.resolve(id, action: allowed ? "allow" : "deny")
        }
        state.onApprovalAlways = { [weak self] id in
            guard let self else { return }
            if let request = self.state.approvals.first(where: { $0.id == id }),
               let rule = request.alwaysAllowRule {
                AlwaysAllowStore.shared.add(rule: rule, cwd: request.cwd)
            }
            self.resolve(id, action: "allow")
        }
        state.onQuestionAnswered = { [weak self] id, answers in
            self?.resolveQuestion(id, answers: answers)
        }
    }

    func handlePreToolUse(_ event: [String: Any], respond: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.state.apply(event: event)

            guard PermissionRules.shouldGate(event) else {
                respond(["action": "passthrough"])
                return
            }

            if AlwaysAllowStore.shared.matches(event) {
                respond([
                    "action": "allow",
                    "reason": "Matches a Perch always-allow rule"
                ])
                return
            }

            let id = UUID().uuidString
            let agent = (event["fv_agent"] as? String) ?? "claude"
            let sessionID = "\(agent):\((event["session_id"] as? String) ?? "")"
            let tool = (event["tool_name"] as? String) ?? "Tool"

            if tool == "AskUserQuestion", let request = Self.parseQuestions(event, id: id, sessionID: sessionID) {
                self.pending[id] = respond
                self.state.addQuestion(request)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.questionTimeout) { [weak self] in
                    self?.resolveQuestion(id, answers: nil)
                }
                return
            }

            self.pending[id] = respond
            self.state.addApproval(ApprovalRequest(
                id: id,
                sessionID: sessionID,
                toolName: tool,
                detail: Self.detail(for: event),
                cwd: (event["cwd"] as? String) ?? "",
                alwaysAllowRule: AlwaysAllowStore.rule(for: event)
            ))

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickTimeout) { [weak self] in
                self?.resolve(id, action: "passthrough")
            }
        }
    }

    private func resolve(_ id: String, action: String) {
        guard let respond = pending.removeValue(forKey: id) else { return }
        state.removeApproval(id)
        respond(["action": action])
    }

    private func resolveQuestion(_ id: String, answers: [(question: String, answers: [String])]?) {
        guard let respond = pending.removeValue(forKey: id) else { return }
        state.removeQuestion(id)
        guard let answers else {
            respond(["action": "passthrough"])
            return
        }
        let summary = answers
            .map { "Q: \($0.question)\nA: \($0.answers.joined(separator: ", "))" }
            .joined(separator: "\n")
        respond([
            "action": "deny",
            "reason": "The user already answered in a GUI dialog. Do not ask again — proceed using these answers:\n\(summary)"
        ])
    }

    private static func parseQuestions(_ event: [String: Any], id: String, sessionID: String) -> QuestionRequest? {
        guard
            let input = event["tool_input"] as? [String: Any],
            let raw = input["questions"] as? [[String: Any]]
        else { return nil }

        let questions = raw.compactMap { item -> QuestionRequest.Question? in
            guard let text = item["question"] as? String else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { option -> QuestionRequest.Option? in
                guard let label = option["label"] as? String else { return nil }
                return QuestionRequest.Option(
                    label: label,
                    description: (option["description"] as? String) ?? ""
                )
            }
            return QuestionRequest.Question(
                text: text,
                header: (item["header"] as? String) ?? "",
                multiSelect: (item["multiSelect"] as? Bool) ?? false,
                options: options
            )
        }
        guard !questions.isEmpty else { return nil }
        return QuestionRequest(id: id, sessionID: sessionID, questions: questions)
    }

    private static func detail(for event: [String: Any]) -> String {
        let input = event["tool_input"] as? [String: Any]
        if let command = input?["command"] as? String { return command }
        if let path = input?["file_path"] as? String { return path }
        if let input, let data = try? JSONSerialization.data(withJSONObject: input),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return ""
    }
}
