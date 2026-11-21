import SwiftUI
import AppKit
import KnifeKit

// ─── Session board: every live agent session on one screen ───
// One card per tab that has claude/codex running: status, the last exchange
// from its transcript, and a reply field that types into that tab. Made for
// clearing a queue of "needs input" without visiting each tab.
//
// Cards sit under the sidebar's own folders (01 OPEN, 02 TODO, …) in sidebar
// order and never reshuffle by status: the ones that want you are marked, not
// moved. A card whose terminal is showing one of Claude's numbered menus (a
// permission prompt, a question) shows that menu with a button per choice.
// Keys: arrows move between cards, return opens one, 1–9 answer its menu,
// esc answers "no" there or, with nothing to answer, closes the board.

struct BoardCardData: Identifiable {
    let tabId: Int
    let agent: String          // "claude" | "codex"
    let messages: [ChatMessage] // the excerpt shown on the card
    let cwd: String?
    var id: Int { tabId }
}

/// A numbered menu on a tab's screen, the way Claude Code draws one:
/// the question above it, then "❯ 1. Yes / 2. … / 3. No".
struct BoardPrompt: Equatable {
    struct Choice: Equatable { let key: String; let label: String }
    var question: [String]
    var choices: [Choice]

    /// Reads the bottom of the screen. Needs two or more numbered lines with the
    /// ❯ selector on one of them, so a numbered list in Claude's reply never reads as a menu.
    static func parse(_ rows: [String]) -> BoardPrompt? {
        let box = CharacterSet(charactersIn: "│┃╭╮╰╯")
        func clean(_ s: String) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.filter { !box.contains($0) }))
                .trimmingCharacters(in: .whitespaces)
        }
        func isRule(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.count >= 8 && t.allSatisfy { "─━═╌┄-╭╮╰╯".contains($0) }
        }
        func choice(_ s: String) -> (Choice, Bool)? {
            var t = Substring(clean(s))
            var marked = false
            if let f = t.first, "❯›>".contains(f) { marked = true; t = t.dropFirst().drop(while: { $0 == " " }) }
            guard let d = t.first, d.isNumber, d != "0",
                  t.dropFirst().hasPrefix(". ") else { return nil }
            let label = t.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { return nil }
            return (Choice(key: String(d), label: label), marked)
        }
        var i = rows.count - 1
        // past the hint lines under a menu ("Esc to cancel", blank rows)
        var skipped = 0
        while i >= 0, choice(rows[i]) == nil, skipped < 6 { i -= 1; skipped += 1 }
        guard i >= 0, choice(rows[i]) != nil else { return nil }
        var found: [(Choice, Bool)] = []
        var wrapped: [String] = [] // a label that ran onto more rows, read bottom-up
        while i >= 0 {
            if let (c, marked) = choice(rows[i]) {
                let label = ([c.label] + wrapped).joined(separator: " ")
                found.insert((Choice(key: c.key, label: label), marked), at: 0)
                wrapped = []; i -= 1; continue
            }
            let t = clean(rows[i])
            // a wrapped row: some choice above it is what it continues
            if !t.isEmpty, !isRule(rows[i]), !found.isEmpty, wrapped.count < 3, i > 0 {
                wrapped.insert(t, at: 0); i -= 1; continue
            }
            break
        }
        i += wrapped.count // rows above the first choice are the question, not a label
        guard found.count >= 2, found.contains(where: { $0.1 }) else { return nil }
        var question: [String] = []
        while i >= 0, question.count < 10, !isRule(rows[i]), !rows[i].contains("╭") {
            let t = clean(rows[i])
            if !t.isEmpty { question.insert(t, at: 0) }
            i -= 1
        }
        return BoardPrompt(question: question, choices: found.map(\.0))
    }
}

struct BoardView: View {
    @ObservedObject var controller: KnifeWindowController
    @ObservedObject var theme = AppModel.shared.theme
    @State private var cards: [BoardCardData] = []
    @State private var prompts: [Int: BoardPrompt] = [:]
    @State private var groups: [Int: (name: String, rank: Int)] = [:]
    @State private var selected: Int?
    @State private var columns = 2
    @State private var refreshing = false
    @FocusState private var focused: Bool
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private static let cardWidth: CGFloat = 400, gap: CGFloat = 14, pad: CGFloat = 18

    var body: some View {
        Group {
            if cards.isEmpty {
                VStack(spacing: 8) {
                    Text("no live agent sessions").font(ui(14)).foregroundStyle(.secondary)
                    Text("open a project from the sidebar").font(ui(12)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                summary
                                ForEach(sections, id: \.name) { section in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 8) {
                                            Text(section.name).font(ui(12, bold: true))
                                            Text("\(section.cards.count)").font(ui(12)).foregroundStyle(.secondary)
                                            let waiting = section.cards.filter { $0.1.status == .needsInput }.count
                                            if waiting > 0 {
                                                Text("\(waiting) need\(waiting == 1 ? "s" : "") you")
                                                    .font(ui(12)).foregroundStyle(theme.attentionColor)
                                            }
                                        }
                                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap, alignment: .top),
                                                                 count: columns),
                                                  alignment: .leading, spacing: Self.gap) {
                                            ForEach(section.cards, id: \.0.id) { card, tab in
                                                SessionCard(tab: tab, messages: card.messages, agent: card.agent,
                                                            prompt: prompts[tab.id], selected: selected == tab.id,
                                                            select: { selected = tab.id },
                                                            open: { open(tab.id) },
                                                            answer: { answer(tab, $0) })
                                                    .id(tab.id)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(Self.pad)
                        }
                        .onChange(of: selected) { _, id in
                            guard let id else { return }
                            withAnimation(.easeOut(duration: 0.15)) { scroll.scrollTo(id) }
                        }
                    }
                    .onAppear { columns = Self.columns(for: geo.size.width) }
                    .onChange(of: geo.size.width) { _, w in columns = Self.columns(for: w) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: theme.nsColor(theme.current.background)))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { move(dx: -1, dy: 0) }
        .onKeyPress(.rightArrow) { move(dx: 1, dy: 0) }
        .onKeyPress(.upArrow) { move(dx: 0, dy: -1) }
        .onKeyPress(.downArrow) { move(dx: 0, dy: 1) }
        .onKeyPress(.return) {
            guard let id = selected else { return .ignored }
            open(id); return .handled
        }
        .onKeyPress(.escape) {
            if let id = selected, prompts[id] != nil, let tab = tab(id) { answer(tab, "\u{1b}"); return .handled }
            controller.showBoard = false; return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let id = selected, let p = prompts[id], let tab = tab(id),
                  p.choices.contains(where: { $0.key == press.characters }) else { return .ignored }
            answer(tab, press.characters); return .handled
        }
        .onAppear { refresh(); focused = true }
        .onReceive(tick) { _ in refresh() }
    }

    private var summary: some View {
        let waiting = cards.compactMap { tab($0.tabId) }.filter { $0.status == .needsInput }.count
        return HStack(spacing: 10) {
            Text("\(cards.count) session\(cards.count == 1 ? "" : "s")").font(ui(13, bold: true))
            if waiting > 0 {
                Text("\(waiting) need\(waiting == 1 ? "s" : "") you").font(ui(13)).foregroundStyle(theme.attentionColor)
            }
            Spacer(minLength: 0)
            Text("arrows move · return opens · 1–9 answers · esc closes").font(ui(11)).foregroundStyle(.secondary)
        }
    }

    private static func columns(for width: CGFloat) -> Int {
        max(1, Int((width - 2 * pad + gap) / (cardWidth + gap)))
    }

    private func tab(_ id: Int) -> TabModel? { controller.tabs.first { $0.id == id } }

    private func open(_ id: Int) {
        controller.activate(id)
        controller.showBoard = false
    }

    /// One key into the tab, the way you'd press it there: Claude's menus take the number alone.
    private func answer(_ tab: TabModel, _ key: String) {
        tab.view.send(txt: key)
        prompts[tab.id] = nil // gone from the card at once; the next read brings it back if it's still up
        selected = tab.id
    }

    /// Folders in sidebar order, a card's place in its folder by tab order: nothing moves on its own.
    private var sections: [(name: String, cards: [(BoardCardData, TabModel)])] {
        let byId = Dictionary(uniqueKeysWithValues: controller.tabs.map { ($0.id, $0) })
        var out: [(name: String, rank: Int, cards: [(BoardCardData, TabModel)])] = []
        for card in cards {
            guard let tab = byId[card.tabId] else { continue }
            let g = groups[card.tabId] ?? (name: "OTHER", rank: Int.max)
            if let i = out.firstIndex(where: { $0.name == g.name }) { out[i].cards.append((card, tab)) }
            else { out.append((name: g.name, rank: g.rank, cards: [(card, tab)])) }
        }
        return out.sorted { $0.rank < $1.rank }.map { (name: $0.name, cards: $0.cards) }
    }

    /// Cards in reading order, row by row, as the grid lays them out.
    private var rows: [[Int]] {
        sections.flatMap { s in
            stride(from: 0, to: s.cards.count, by: columns).map { i in
                s.cards[i..<min(i + columns, s.cards.count)].map(\.0.tabId)
            }
        }
    }

    private func move(dx: Int, dy: Int) -> KeyPress.Result {
        let rows = self.rows
        guard !rows.isEmpty else { return .ignored }
        guard let id = selected, let r = rows.firstIndex(where: { $0.contains(id) }),
              let c = rows[r].firstIndex(of: id) else {
            selected = rows[0][0]; return .handled
        }
        if dy != 0 {
            let nr = min(max(r + dy, 0), rows.count - 1)
            selected = rows[nr][min(c, rows[nr].count - 1)]
        } else {
            let flat = rows.flatMap { $0 }
            let i = flat.firstIndex(of: id)! + dx
            selected = flat[min(max(i, 0), flat.count - 1)]
        }
        return .handled
    }

    /// The sidebar folder a session's project is filed in ("04 UN / GRANTS"), and where that
    /// folder sits in the sidebar. A project that isn't in a folder goes under OTHER, last.
    static func folderGroups(_ cards: [BoardCardData], meta: Projects.SidebarMeta) -> [Int: (name: String, rank: Int)] {
        guard let tree = meta.tree else { return [:] }
        var rank: [String: Int] = [:]
        func walk(_ parent: String?, _ s: ProjectSection) {
            for f in tree.children(of: parent, in: s) where rank[f.id] == nil {
                rank[f.id] = rank.count; walk(f.id, s)
            }
        }
        for s in ProjectSection.allCases { walk(nil, s) }
        var out: [Int: (name: String, rank: Int)] = [:]
        for card in cards {
            guard let cwd = card.cwd,
                  let path = tree.place.keys.filter({ cwd == $0 || cwd.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }),
                  let leaf = tree.place[path] else { continue }
            var names: [String] = [], cur: String? = leaf
            for _ in 0...tree.folders.count {
                guard let c = cur, let f = tree.folder(c) else { break }
                names.insert(f.name, at: 0); cur = f.parent
            }
            guard !names.isEmpty else { continue }
            out[card.tabId] = (names.joined(separator: " / "), rank[leaf] ?? Int.max - 1)
        }
        return out
    }

    private func readPrompts() {
        var next: [Int: BoardPrompt] = [:]
        for card in cards {
            guard let tab = tab(card.tabId) else { continue }
            let t = tab.view.getTerminal()
            let screen = (0..<t.rows).map { t.getLine(row: $0)?.translateToString(trimRight: true) ?? "" }
            if let p = BoardPrompt.parse(screen) { next[tab.id] = p }
        }
        if next != prompts { prompts = next }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        // Snapshot on the main actor; the pid lookups and transcript reads happen
        // off it. The shell's real cwd is the one that matters: a tab opened with
        // ⌘T has no launch cwd at all, and `cd`-ing doesn't change the one it was
        // opened with, so both would leave the card blank.
        let snap = controller.tabs.map {
            (id: $0.id, pid: $0.shellPid, fallback: $0.lastReportedCwd ?? $0.opts.cwd,
             source: TranscriptReader.source(for: $0, cwd: nil))
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let byShell = TabModel.agentsByShell(Set(snap.map(\.pid).filter { $0 > 0 }))
            let fresh = snap.compactMap { t -> BoardCardData? in
                guard t.pid > 0, let agent = byShell[t.pid] else { return nil }
                let cwd = TabModel.cwdOf(pid: t.pid) ?? t.fallback
                var src = t.source; src.cwd = cwd
                let all = TranscriptReader.chat(src)?.msgs ?? []
                return BoardCardData(tabId: t.id, agent: agent, messages: Self.excerpt(all), cwd: cwd)
            }
            let meta = Projects.loadMeta()
            let grouped = Self.folderGroups(fresh, meta: meta)
            DispatchQueue.main.async {
                cards = fresh
                groups = grouped
                readPrompts()
                if let s = selected, !fresh.contains(where: { $0.tabId == s }) { selected = nil }
                refreshing = false
            }
        }
    }

    /// The last thing you said and everything since, capped so cards stay readable.
    static func excerpt(_ msgs: [ChatMessage]) -> [ChatMessage] {
        let fromUser = msgs.lastIndex { $0.kind == .user }.map { Array(msgs[$0...]) } ?? msgs
        return Array(fromUser.suffix(10))
    }
}

struct SessionCard: View {
    @ObservedObject var tab: TabModel
    let messages: [ChatMessage]
    let agent: String
    let prompt: BoardPrompt?
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    let answer: (String) -> Void
    @ObservedObject var theme = AppModel.shared.theme
    @State private var draft = ""
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // Same height for every card; long exchanges scroll, newest at the bottom.
            ScrollView {
                body_.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let prompt { menu(prompt) }
            footer
        }
        .padding(14)
        .frame(height: 460)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(border, lineWidth: selected || tab.status == .needsInput ? 2 : 1))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { select() })
    }

    private var border: Color {
        if tab.status == .needsInput || prompt != nil { return theme.attentionColor }
        return selected ? theme.accentColor : Color.primary.opacity(0.12)
    }

    private var isPulsing: Bool { tab.working && !tab.attention }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tab.attention ? theme.attentionColor : (tab.working ? theme.accentColor : .clear))
                .frame(width: 8, height: 8)
                .opacity(isPulsing && pulse ? 0.25 : 1.0)
                .animation(isPulsing ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: pulse)
                .onAppear { pulse = isPulsing }
                .onChange(of: isPulsing) { _, now in pulse = now }
            Text(tab.emoji).font(.system(size: 14))
            (Text(tab.title) + Text(tab.context.map { " | " + $0 } ?? "").foregroundColor(.secondary))
                .font(ui(14, bold: true)).lineLimit(1)
            Spacer(minLength: 0)
            Text(statusWord)
                .font(ui(12))
                .foregroundStyle(tab.status == .needsInput || prompt != nil ? theme.attentionColor : Color.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .help("open this tab")
        // set(), not push/pop: a card that redraws while hovered never pops,
        // which left the pointing hand stuck everywhere
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var statusWord: String {
        if prompt != nil { return "waiting on you" }
        switch tab.status {
        case .idle: return agent
        case .working: return "working…"
        case .ready: return "ready"
        case .needsInput: return "needs input"
        }
    }

    /// The question on the tab's screen and a button per choice; esc is Claude's "no".
    private func menu(_ p: BoardPrompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !p.question.isEmpty {
                Text(p.question.joined(separator: "\n")).font(ui(12))
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            ForEach(p.choices, id: \.key) { c in
                Button { answer(c.key) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(c.key).font(ui(12, bold: true)).frame(width: 12)
                        Text(c.label).font(ui(13)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { answer("\u{1b}") } label: {
                Text("esc  cancel").font(ui(11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.attentionColor.opacity(0.10)))
    }

    @ViewBuilder
    private var body_: some View {
        if messages.isEmpty {
            Text("no transcript yet").font(ui(12)).foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(messages) { m in
                    switch m.kind {
                    case .user:
                        HStack {
                            Spacer(minLength: 28)
                            Text(markdown(m.text)).font(ui(13))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(theme.accentColor.opacity(0.18)))
                        }
                    case .assistant:
                        Text(markdown(m.text)).font(ui(13))
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    case .tool:
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            Text(m.text).font(Font.custom("JetBrains Mono", size: 12)).lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            TextField("reply…", text: $draft)
                .textFieldStyle(.plain)
                .font(ui(13))
                .onSubmit(send)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            Button("send", action: send)
                .buttonStyle(.plain)
                .font(ui(12))
                .foregroundStyle(draft.isEmpty ? Color.secondary : theme.accentColor)
                .disabled(draft.isEmpty)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Text and Enter in one chunk reads as a paste to TUIs; send the CR later (same as phone input).
        let view = tab.view
        view.send(txt: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { view.send(txt: "\r") }
        draft = ""
    }
}
