import SwiftUI

enum Style {
    static let background = Color.black
    static let cardBackground = Color(white: 0.045)
    static let hoverBackground = Color(white: 0.08)
    static let border = Color(white: 0.16)
    static let borderStrong = Color(white: 0.30)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.63)
    static let textTertiary = Color(white: 0.42)

    // One accent: amber for "needs you", red reserved for destructive
    static var accent: Color { Prefs.shared.accentColor }
    static let red = Color(red: 0.95, green: 0.38, blue: 0.40)
    static let green = Color(red: 0.36, green: 0.84, blue: 0.47)

    // Dark at the top so the island blends into the menu bar; the silver
    // sheen sits along the lower edge instead
    static let islandBorder = LinearGradient(
        stops: [
            .init(color: Color(white: 0.06), location: 0),
            .init(color: Color(white: 0.16), location: 0.45),
            .init(color: Color(white: 0.38), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let sessionBorder = LinearGradient(
        colors: [Color(white: 0.42), Color(white: 0.18)],
        startPoint: .top,
        endPoint: .bottom
    )

    // Type scale: 13 title / 11 body / 10 micro
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(geistName(for: weight), size: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(weight == .medium || weight == .semibold ? "GeistMono-Medium" : "GeistMono-Regular", size: size)
    }

    private static func geistName(for weight: Font.Weight) -> String {
        switch weight {
        case .semibold, .bold: "Geist-SemiBold"
        case .medium: "Geist-Medium"
        default: "Geist-Regular"
        }
    }
}

struct StatusSquare: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                guard Prefs.shared.staggeredAnimations else {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(Double(index) * 0.05)) {
                    shown = true
                }
            }
    }
}

// Small pulsing dot alternative to the cube for "working"
struct PulsingDotView: View {
    @State private var bright = false

    var body: some View {
        Rectangle()
            .fill(Style.textSecondary.opacity(bright ? 1 : 0.35))
            .frame(width: 6, height: 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    bright = true
                }
            }
    }
}

// Picks the configured "working" indicator
struct WorkingIndicatorView: View {
    let size: CGFloat

    var body: some View {
        switch Prefs.shared.workingIndicator {
        case "dot":
            PulsingDotView()
                .frame(width: size, height: size)
        case "none":
            StatusSquare(color: Style.textSecondary)
                .frame(width: size, height: size)
        default:
            RubiksCubeView()
                .frame(width: size, height: size)
        }
    }
}

// Notch-style outline: the top corners flare outward with concave "ears"
// that blend into the menu bar, like the hardware notch
struct NotchShape: InsettableShape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 0) {
            if state.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .offset(y: -8)))
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        // Keep content inside the shape's body — the ears inset the sides
        .padding(.horizontal, notchShape.topRadius)
        .frame(
            width: state.isExpanded
                ? NotchPanelController.expandedSize.width
                : collapsedWidth,
            height: state.isExpanded
                ? NotchPanelController.expandedSize.height
                : NotchPanelController.collapsedSize.height
        )
        .background(notchShape.fill(Style.background))
        .overlay(
            // Extend the stroke shape past the top so the border's top line
            // is clipped away — the island must meet the screen edge seamlessly.
            // Collapsed, the island should read as the bare hardware notch,
            // so the outline only shows while expanded
            notchShape
                .strokeBorder(Style.islandBorder, lineWidth: 1)
                .padding(.top, -2)
                .drawingGroup()
                .opacity(state.isExpanded ? 1 : 0)
                .allowsHitTesting(false)
        )
        .clipShape(notchShape)
        .onHover { hovering in
            state.setHovering(hovering)
        }
        .animation(.spring(response: 0.34, dampingFraction: 1.0), value: state.isExpanded)
        .animation(.spring(response: 0.34, dampingFraction: 1.0), value: collapsedWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private var notchShape: NotchShape {
        NotchShape(topRadius: 12, bottomRadius: 16)
    }

    // A running or attention-needing agent stretches the island so its
    // activity line has room; quiet stays hardware-notch sized
    private var collapsedWidth: CGFloat {
        let active = state.sessions.contains {
            $0.status == .working || $0.status == .waitingForApproval || $0.status == .waitingForAnswer
        }
        guard active, prefs.collapsedShowsActivity else { return NotchPanelController.collapsedSize.width }
        return min(prefs.collapsedActiveWidth, NotchPanelController.expandedSize.width)
    }

    private var collapsedContent: some View {
        HStack(spacing: 8) {
            collapsedIndicator
            Text(collapsedSummary)
                .font(Style.mono(11, .medium))
                .foregroundStyle(Style.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var collapsedIndicator: some View {
        if needsAttention {
            StatusSquare(color: Style.accent)
        } else if state.sessions.contains(where: { $0.status == .working }) {
            WorkingIndicatorView(size: 22)
        } else {
            StatusSquare(color: Style.textTertiary)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let approval = state.approvals.first {
                ApprovalCardView(
                    approval: approval,
                    decide: { allowed in
                        state.onApprovalDecision?(approval.id, allowed)
                    },
                    always: {
                        state.onApprovalAlways?(approval.id)
                    }
                )
                .padding(.top, 14)
                .modifier(StaggeredAppear(index: 0))
            } else if let question = state.questions.first {
                QuestionCardView(request: question) { answers in
                    state.onQuestionAnswered?(question.id, answers)
                }
                .id(question.id)
                .padding(.top, 14)
                .modifier(StaggeredAppear(index: 0))
            } else if state.showNewSession {
                NewSessionView(state: state)
                    .padding(.top, 14)
                    .modifier(StaggeredAppear(index: 0))
            } else if let spotlight = state.spotlightSession {
                ResponseSpotlightView(
                    session: spotlight,
                    totalSessions: state.sessions.count,
                    dismiss: { state.dismissSpotlight() },
                    close: {
                        state.dismissSpotlight()
                        state.collapseNow()
                    },
                    jump: { TerminalJumper.jump(to: spotlight) }
                )
                .padding(.top, 14)
                .modifier(StaggeredAppear(index: 0))
            } else {
                HStack {
                    Text("Sessions")
                        .font(Style.sans(11, .medium))
                        .foregroundStyle(Style.textTertiary)
                    Spacer()
                    HoverIconButton(systemName: "plus") {
                        state.showNewSession = true
                    }
                    HoverIconButton(systemName: "gearshape") {
                        state.collapseNow()
                        state.onOpenSettings?()
                    }
                }
                .padding(.top, 14)
                .modifier(StaggeredAppear(index: 0))

                if state.sessions.isEmpty {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .modifier(StaggeredAppear(index: 1))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(Array(state.sessions.enumerated()), id: \.element.id) { index, session in
                                SessionRowView(session: session) {
                                    TerminalJumper.debugLog("row tapped: \(session.id)")
                                    TerminalJumper.jump(to: session)
                                }
                                .modifier(StaggeredAppear(index: index + 1))
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if prefs.showUsageFooter,
               state.approvals.isEmpty, state.questions.isEmpty, !state.showNewSession,
               state.spotlightSession == nil,
               let usage = state.usage, !usage.windows.isEmpty || usage.needsLogin {
                UsageFooterView(usage: usage) {
                    OAuthLogin.shared.start { _ in
                        UsageTracker.shared.forceRefresh { snapshot in
                            state.usage = snapshot
                        }
                    }
                }
                .modifier(StaggeredAppear(index: 2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var needsAttention: Bool {
        state.sessions.contains {
            $0.status == .waitingForApproval || $0.status == .waitingForAnswer
        }
    }

    private var collapsedSummary: String {
        let attention = state.sessions.filter {
            $0.status == .waitingForApproval || $0.status == .waitingForAnswer
        }
        if let first = attention.first {
            return "\(first.agentName): \(first.status.rawValue)"
        }
        let working = state.sessions.filter { $0.status == .working }
        guard !working.isEmpty else { return "All quiet" }

        // Narrate the most recent concrete action; fall back to what the
        // model is saying, and only then to a bare "Thinking…"
        let byRecency = working.sorted { $0.lastUpdated > $1.lastUpdated }
        let activity = byRecency.first { !$0.lastActivity.isEmpty && $0.lastActivity != "Thinking…" }?.lastActivity
            ?? byRecency.first { !$0.narration.isEmpty }?.narration
            ?? byRecency.first { !$0.lastActivity.isEmpty }?.lastActivity
        if let activity {
            return working.count > 1 ? "\(working.count) · \(activity)" : activity
        }
        return "\(working.count) agent\(working.count == 1 ? "" : "s") working"
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            // Ghost 3x3 grid echoing the cube
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Color(white: 0.12))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
            VStack(spacing: 2) {
                Text("No active sessions")
                    .font(Style.sans(11, .medium))
                    .foregroundStyle(Style.textSecondary)
                Text("Start an agent session to see it here")
                    .font(Style.sans(10))
                    .foregroundStyle(Style.textTertiary)
            }
        }
    }
}

struct HoverIconButton: View {
    let systemName: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(hovered ? Style.textPrimary : Style.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

struct SharpButton: View {
    enum Variant {
        case primary, secondary, destructive
    }

    let title: String
    let variant: Variant
    var expand = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Style.sans(11, .semibold))
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .frame(maxWidth: expand ? .infinity : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(SharpButtonPressStyle(variant: variant, hovered: hovered))
        .onHover { hovering in
            hovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

struct SharpButtonPressStyle: ButtonStyle {
    let variant: SharpButton.Variant
    let hovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background)
            .overlay(Rectangle().strokeBorder(borderColor, lineWidth: 1))
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var background: Color {
        switch variant {
        case .primary: hovered ? Color(white: 0.85) : Style.textPrimary
        case .secondary: hovered ? Style.hoverBackground : Style.background
        case .destructive: hovered ? Style.red.opacity(0.10) : Style.background
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: Style.background
        case .secondary: Style.textPrimary
        case .destructive: Style.red
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: .clear
        case .secondary: hovered ? Style.borderStrong : Style.border
        case .destructive: hovered ? Style.red.opacity(0.6) : Style.border
        }
    }
}

struct UsageFooterView: View {
    let usage: UsageSnapshot
    var onConnect: (() -> Void)?

    @State private var connecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if usage.windows.isEmpty, usage.needsLogin {
                HStack(spacing: 8) {
                    Text(connecting ? "Waiting for approval in your browser…" : "Usage quota not connected")
                        .font(Style.mono(10))
                        .foregroundStyle(Style.textTertiary)
                    Spacer()
                    if !connecting {
                        SharpButton(title: "Connect", variant: .secondary) {
                            connecting = true
                            onConnect?()
                        }
                    }
                }
            }
            ForEach(usage.windows, id: \.label) { window in
                row(window)
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Style.border)
                .frame(height: 1)
        }
        .onChange(of: usage.computedAt) {
            connecting = false
        }
    }

    private func row(_ window: QuotaWindow) -> some View {
        let fraction = min(max(window.utilization / 100, 0), 1)
        let barColor = window.utilization >= 80 ? Style.accent : Color(white: 0.55)

        return HStack(spacing: 8) {
            Text(window.label)
                .font(Style.mono(10, .medium))
                .foregroundStyle(Style.textTertiary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(white: 0.12))
                    Rectangle()
                        .fill(barColor)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
            Text("\(Int(window.utilization.rounded()))%")
                .font(Style.mono(10, .medium))
                .foregroundStyle(Style.textSecondary)
                .frame(width: 32, alignment: .trailing)
            Text(Self.resetText(window.resetsAt))
                .font(Style.mono(10))
                .foregroundStyle(Style.textTertiary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private static func resetText(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "—" }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return "resetting" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct ApprovalCardView: View {
    let approval: ApprovalRequest
    let decide: (Bool) -> Void
    let always: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusSquare(color: Style.accent)
                Text("\(approval.toolName) needs approval")
                    .font(Style.sans(13, .semibold))
                    .foregroundStyle(Style.textPrimary)
            }

            if !approval.detail.isEmpty {
                ScrollView {
                    Text(approval.detail)
                        .font(Style.mono(11))
                        .foregroundStyle(Style.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(8)
                .background(Style.cardBackground)
                .overlay(Rectangle().strokeBorder(Style.border, lineWidth: 1))
            }

            HStack(spacing: 8) {
                SharpButton(title: "Allow", variant: .primary, expand: true) {
                    decide(true)
                }
                if approval.alwaysAllowRule != nil {
                    SharpButton(title: "Always Allow", variant: .secondary) {
                        always()
                    }
                }
                SharpButton(title: "Deny", variant: .destructive) {
                    decide(false)
                }
            }

            if let rule = approval.alwaysAllowRule {
                Text("Always Allow saves \(rule) for this project")
                    .font(Style.mono(10))
                    .foregroundStyle(Style.textTertiary)
            }
        }
    }
}

struct SharpCheckbox: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(selected ? Style.textPrimary : Style.border, lineWidth: 1)
                .frame(width: 12, height: 12)
            if selected {
                Rectangle()
                    .fill(Style.textPrimary)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct QuestionCardView: View {
    let request: QuestionRequest
    let submit: ([(question: String, answers: [String])]) -> Void

    @State private var index = 0
    @State private var collected: [(question: String, answers: [String])] = []
    @State private var selected: Set<String> = []

    private var current: QuestionRequest.Question {
        request.questions[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusSquare(color: Style.accent)
                if !current.header.isEmpty {
                    Text(current.header.uppercased())
                        .font(Style.sans(10, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Style.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().strokeBorder(Style.borderStrong, lineWidth: 1))
                }
                if request.questions.count > 1 {
                    Text("\(index + 1)/\(request.questions.count)")
                        .font(Style.mono(10))
                        .foregroundStyle(Style.textTertiary)
                }
            }

            Text(current.text)
                .font(Style.sans(13, .semibold))
                .foregroundStyle(Style.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(current.options.enumerated()), id: \.element.label) { optionIndex, option in
                        optionRow(option)
                            .modifier(StaggeredAppear(index: optionIndex))
                        if optionIndex < current.options.count - 1 {
                            Rectangle()
                                .fill(Style.border)
                                .frame(height: 1)
                        }
                    }
                }
            }

            if current.multiSelect {
                SharpButton(title: "Submit", variant: .primary, expand: true) {
                    advance(with: Array(selected))
                }
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.4 : 1)
            }
        }
    }

    private func optionRow(_ option: QuestionRequest.Option) -> some View {
        QuestionOptionRow(
            option: option,
            multiSelect: current.multiSelect,
            selected: selected.contains(option.label)
        ) {
            if current.multiSelect {
                if selected.contains(option.label) {
                    selected.remove(option.label)
                } else {
                    selected.insert(option.label)
                }
            } else {
                advance(with: [option.label])
            }
        }
    }

    private func advance(with answers: [String]) {
        collected.append((question: current.text, answers: answers))
        selected = []
        if index + 1 < request.questions.count {
            index += 1
        } else {
            submit(collected)
        }
    }
}

struct QuestionOptionRow: View {
    let option: QuestionRequest.Option
    let multiSelect: Bool
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if multiSelect {
                    SharpCheckbox(selected: selected)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(Style.sans(11, .medium))
                        .foregroundStyle(Style.textPrimary)
                    if !option.description.isEmpty {
                        Text(option.description)
                            .font(Style.sans(10))
                            .foregroundStyle(Style.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(hovered ? Style.hoverBackground : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

// Two bright silver segments orbiting the row's outline while it works —
// an angular gradient with two comet arcs, spun continuously and masked
// down to the 1px border stroke
struct SpinningBorderView: View {
    @State private var angle = 0.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let diagonal = (size.width * size.width + size.height * size.height).squareRoot()

            ZStack {
                Rectangle()
                    .strokeBorder(Color(white: 0.20), lineWidth: 1)
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color(white: 0.92), location: 0.14),
                        .init(color: .clear, location: 0.26),
                        .init(color: .clear, location: 0.5),
                        .init(color: Color(white: 0.92), location: 0.64),
                        .init(color: .clear, location: 0.76),
                        .init(color: .clear, location: 1)
                    ],
                    center: .center
                )
                .frame(width: diagonal, height: diagonal)
                .rotationEffect(.degrees(angle))
                .position(x: size.width / 2, y: size.height / 2)
                .mask(Rectangle().strokeBorder(lineWidth: 1))
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}

// NSCursor.push from a non-activated app gets ignored — cursorUpdate events
// via an .activeAlways tracking area work even while the app is inactive.
// hitTest returns nil so clicks pass through to the SwiftUI row underneath.
struct PointerCursorOverlay: NSViewRepresentable {
    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.pointingHand.set()
        }
    }

    func makeNSView(context: Context) -> NSView { CursorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct LinkPointer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content
        }
    }
}

struct SessionRowView: View {
    let session: AgentSession
    let action: () -> Void

    @ObservedObject private var prefs = Prefs.shared
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            if session.status == .working {
                WorkingIndicatorView(size: 26)
            } else {
                StatusSquare(color: statusColor)
                    .frame(width: 26)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleLine)
                    .font(Style.sans(11, .semibold))
                    .foregroundStyle(Style.textPrimary)
                    .lineLimit(1)
                if prefs.showPromptLine, !session.lastPrompt.isEmpty {
                    (Text("You: ").foregroundStyle(Style.textTertiary)
                        + Text(session.lastPrompt).foregroundStyle(Style.textSecondary))
                        .font(Style.mono(10))
                        .lineLimit(1)
                }
                activityLine
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if needsAttention {
                    Text(session.status.rawValue.uppercased())
                        .font(Style.sans(9, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Style.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().strokeBorder(Style.accent.opacity(0.45), lineWidth: 1))
                } else {
                    Text(agentShortName)
                        .font(Style.sans(9, .semibold))
                        .foregroundStyle(Style.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().strokeBorder(Style.accent.opacity(0.35), lineWidth: 1))
                }
                if prefs.showRelativeTime {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(Self.relativeTime(session.lastUpdated))
                            .font(Style.mono(9))
                            .foregroundStyle(Style.textTertiary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(hovered ? Style.hoverBackground : Style.cardBackground)
        .overlay {
            if session.status == .working, prefs.spinningBorderEnabled {
                SpinningBorderView()
            } else {
                Rectangle()
                    .strokeBorder(Style.sessionBorder, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .overlay(PointerCursorOverlay())
        .modifier(LinkPointer())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    private var titleLine: String {
        let project = (session.cwd as NSString).lastPathComponent
        let name = project.isEmpty ? session.directory : project
        return session.title.isEmpty ? name : "\(name) · \(session.title)"
    }

    private var needsAttention: Bool {
        session.status == .waitingForApproval || session.status == .waitingForAnswer
    }

    private var agentShortName: String {
        String(session.agentName.split(separator: " ").first ?? "Agent")
    }

    @ViewBuilder
    private var activityLine: some View {
        if !session.toolName.isEmpty {
            (Text(session.toolName).foregroundStyle(Style.accent)
                + Text(session.toolDetail.isEmpty ? "" : "  " + session.toolDetail)
                    .foregroundStyle(Style.textTertiary))
                .font(Style.mono(10, .medium))
                .lineLimit(1)
        } else if !session.narration.isEmpty {
            Text(session.narration)
                .font(Style.mono(10))
                .foregroundStyle(Style.textTertiary)
                .lineLimit(1)
        } else {
            Text(session.lastActivity)
                .font(Style.mono(10))
                .foregroundStyle(Style.textTertiary)
                .lineLimit(1)
        }
    }

    private static func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "<1m" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h" : "\(hours / 24)d"
    }

    private var statusColor: Color {
        switch session.status {
        case .working: Style.textSecondary
        case .waitingForApproval, .waitingForAnswer: Style.accent
        case .idle: Style.textTertiary
        case .done: Style.textPrimary
        }
    }
}

// Auto-shown when a session finishes: the session row, then a card with the
// prompt that was asked and the full final response
struct ResponseSpotlightView: View {
    let session: AgentSession
    let totalSessions: Int
    let dismiss: () -> Void
    let close: () -> Void
    let jump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionRowView(session: session, action: jump)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if session.lastPrompt.isEmpty {
                        Text(session.agentName)
                            .font(Style.mono(10, .medium))
                            .foregroundStyle(Style.textSecondary)
                    } else {
                        (Text("You: ").foregroundStyle(Style.textTertiary)
                            + Text(session.lastPrompt).foregroundStyle(Style.textPrimary))
                            .font(Style.mono(10, .medium))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("Done")
                        .font(Style.sans(10, .medium))
                        .foregroundStyle(Style.textTertiary)
                    HoverIconButton(systemName: "xmark", action: close)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Rectangle()
                    .fill(Style.border)
                    .frame(height: 1)

                ScrollView(showsIndicators: false) {
                    Text(session.lastResponse.isEmpty ? "Reading response…" : session.lastResponse)
                        .font(Style.mono(11))
                        .foregroundStyle(session.lastResponse.isEmpty ? Style.textTertiary : Style.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
            .background(Style.cardBackground)
            .overlay(Rectangle().strokeBorder(Style.border, lineWidth: 1))
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                HoverRowButton(action: close) {
                    Text("Okay")
                        .font(Style.sans(11, .medium))
                        .foregroundStyle(Style.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .overlay(Rectangle().strokeBorder(Style.green.opacity(0.6), lineWidth: 1))

                HoverRowButton(action: dismiss) {
                    Text("Show all \(totalSessions) session\(totalSessions == 1 ? "" : "s")")
                        .font(Style.sans(11))
                        .foregroundStyle(Style.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .overlay(Rectangle().strokeBorder(Style.borderStrong, lineWidth: 1))
            }
        }
    }
}

struct NewSessionView: View {
    @ObservedObject var state: NotchState

    @State private var agent = Prefs.shared.defaultAgent

    private static let agents = [
        ("claude", "Claude"),
        ("codex", "Codex"),
        ("gemini", "Gemini"),
        ("opencode", "OpenCode"),
        ("cursor-agent", "Cursor")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HoverIconButton(systemName: "chevron.left") {
                    state.showNewSession = false
                }
                Text("New session")
                    .font(Style.sans(11, .semibold))
                    .foregroundStyle(Style.textPrimary)
                Spacer()
                ForEach(Self.agents, id: \.0) { id, label in
                    agentChip(id: id, label: label)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(state.recentDirectories, id: \.self) { dir in
                        directoryRow(dir)
                        Rectangle()
                            .fill(Style.border)
                            .frame(height: 1)
                    }
                    chooseFolderRow
                }
            }
            .background(Style.cardBackground)
            .overlay(Rectangle().strokeBorder(Style.border, lineWidth: 1))
        }
    }

    private func agentChip(id: String, label: String) -> some View {
        Button {
            agent = id
        } label: {
            Text(label.uppercased())
                .font(Style.sans(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(agent == id ? Style.background : Style.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(agent == id ? Style.textPrimary : .clear)
                .overlay(Rectangle().strokeBorder(
                    agent == id ? .clear : Style.border, lineWidth: 1
                ))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func directoryRow(_ dir: String) -> some View {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shown = dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
        return rowButton(icon: "folder", title: (dir as NSString).lastPathComponent, subtitle: shown) {
            launch(dir)
        }
    }

    private var chooseFolderRow: some View {
        rowButton(icon: "ellipsis", title: "Choose folder…", subtitle: "") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                launch(url.path)
            }
        }
    }

    private func rowButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HoverRowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(Style.textTertiary)
                    .frame(width: 14)
                Text(title)
                    .font(Style.sans(11, .medium))
                    .foregroundStyle(Style.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Style.mono(10))
                        .foregroundStyle(Style.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
        }
    }

    private func launch(_ directory: String) {
        let chosen = agent
        DispatchQueue.global(qos: .userInitiated).async {
            AgentController.launchSession(agent: chosen, directory: directory)
        }
        state.showNewSession = false
    }
}

struct HoverRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content
                .background(hovered ? Style.hoverBackground : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
