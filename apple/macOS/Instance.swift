import Foundation
import KnifeKit

/// Which Knife this is. The main app runs against Claude Code's default account (~/.claude, ~/.claude.json).
/// A second copy (`make install-mac-2`: its own bundle id, so its own windows, tabs and sidebar settings) runs
/// against another account's CLAUDE_CONFIG_DIR: its shells get that variable, its sidebar, trust and hooks use
/// that account's files, it listens on its own socket, and it tints itself so the two can't be confused.
/// All of it comes from Info.plist keys set at build time; empty values mean the main app.
enum Instance {
    private static func info(_ key: String) -> String? {
        let v = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
        return v?.isEmpty == false ? v : nil
    }

    /// KnifeInstance: "2" for the second app, nil for the main one.
    static let id: String? = info("KnifeInstance")
    static var isSecondary: Bool { id != nil }

    /// KnifeClaudeConfigDir (e.g. ~/.claude-worker), tilde expanded — what the tabs export as CLAUDE_CONFIG_DIR.
    static let claudeConfigDir: String? = info("KnifeClaudeConfigDir").map { ($0 as NSString).expandingTildeInPath }

    /// Claude Code's own layout: settings, projects/ and CLAUDE.md live in the config dir, and .claude.json
    /// sits inside it when CLAUDE_CONFIG_DIR is set, next to it (in ~) when it isn't.
    static var claudeDir: String { claudeConfigDir ?? NSHomeDirectory() + "/.claude" }
    static var claudeJSON: String { claudeConfigDir.map { $0 + "/.claude.json" } ?? NSHomeDirectory() + "/.claude.json" }

    /// The alert/control socket. Tabs export it as KNIFE_SOCK so hooks and knife-job.sh answer the app that
    /// started them, whichever account's settings the hook came from.
    static var socketPath: String { NSHomeDirectory() + "/" + (id.map { ".knife-\($0).sock" } ?? ".knife-terminal.sock") }

    /// Application Support folder for session.json.
    static var supportFolder: String { "Knife Terminal" + (id.map { " \($0)" } ?? "") }

    /// Footer label in front of the version.
    static var label: String { id.map { "knife \($0) · " } ?? "" }

    /// KnifeTint (hex, e.g. 3FAF6C): the hue the second app washes its background and accent with.
    static let tint: TermTheme.RGB? = info("KnifeTint").flatMap { UInt32($0.replacingOccurrences(of: "#", with: ""), radix: 16) }.map(TermTheme.RGB.init)

    /// The base palette, tinted when KnifeTint is set — enough to tell the windows apart at a glance
    /// without touching the ANSI colors programs draw with.
    static func theme(_ base: TermTheme, dark: Bool) -> TermTheme {
        guard let t = tint else { return base }
        let white = TermTheme.RGB(0xffffff), black = TermTheme.RGB(0x000000)
        return base.tinted(background: mix(base.background, t, dark ? 0.14 : 0.07),
                           accent: dark ? mix(t, white, 0.3) : mix(t, black, 0.15))
    }

    private static func mix(_ a: TermTheme.RGB, _ b: TermTheme.RGB, _ f: Double) -> TermTheme.RGB {
        func ch(_ x: UInt8, _ y: UInt8) -> UInt32 { UInt32((Double(x) + (Double(y) - Double(x)) * f).rounded()) }
        return TermTheme.RGB(ch(a.r, b.r) << 16 | ch(a.g, b.g) << 8 | ch(a.b, b.b))
    }
}
