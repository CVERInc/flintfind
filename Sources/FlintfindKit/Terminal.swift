import Foundation

/// The terminal half: everything that decides how an answer LOOKS, none of what it is.
///
/// It lives in the library rather than in the CLI target for one reason — the self-test can reach
/// it. `link()` in particular has a rule worth a gate (percent-encode the spaces, leave the slashes
/// alone) and a rule that is invisible until it breaks (fall back to the FULL url, not the pretty
/// short form).
public enum Terminal {

    public static let dim = "\u{1B}[2m", bold = "\u{1B}[1m", cyan = "\u{1B}[36m"
    public static let yellow = "\u{1B}[33m", green = "\u{1B}[32m", reset = "\u{1B}[0m"

    /// Three readable segments, or the whole thing if it is already short.
    public static func short(_ path: String, home: String = NSHomeDirectory()) -> String {
        let p = path.replacingOccurrences(of: home, with: "~")
        let parts = p.components(separatedBy: "/")
        return parts.count > 3 ? parts.suffix(3).joined(separator: "/") : p
    }

    /// Terminals that render OSC 8, so a result can be three readable path segments AND open the
    /// file. Checked by name rather than by TERM: `xterm-ghostty` says which emulator, not which
    /// features, and a terminal that does not know the sequence prints its payload as garbage
    /// across the line.
    public static var hyperlinks: Bool {
        let t = (ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? "").lowercased()
        return ["ghostty", "iterm.app", "wezterm", "vscode"].contains(t)
    }

    /// A clickable path.
    ///
    /// Spaces have to be percent-encoded or the URL stops at the first one — and the path that
    /// matters most here, iCloud's "Mobile Documents", has one. Everything else is left alone:
    /// over-encoding turns the slashes into %2F and the link into nothing.
    ///
    /// Where OSC 8 is unavailable the fallback is the FULL file:// URL, not the pretty short form —
    /// losing the label costs a little width, losing the path costs the whole point.
    public static func link(_ path: String, label: String? = nil, hyper: Bool? = nil) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "/")
        let url = "file://" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
        guard hyper ?? hyperlinks else { return url }
        return "\u{1B}]8;;\(url)\u{1B}\\\(label ?? short(path))\u{1B}]8;;\u{1B}\\"
    }

    /// Where this tool keeps its own state. `~/.flintfind`, not next to the binary: the Python
    /// version wrote beside its script, which a compiled binary has no equivalent of.
    public static var stateDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".flintfind")
    }

    /// Write what was asked and how it went, to a local file that never leaves this machine.
    ///
    /// Any scheme that asks a person to write down what went wrong comes back empty; the honest way
    /// to learn what fails is to read what they actually typed — especially the queries they
    /// abandoned and retyped a moment later. Delete it to erase it; nothing else reads it.
    public static func log(terms: [String], files: Int, shown: Int, seconds: Double) {
        let dir = stateDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("queries.log")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(fmt.string(from: Date()))\t\(String(format: "%.2f", seconds))\t\(files)\t\(shown)\t\(terms.joined(separator: " "))\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: path) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
