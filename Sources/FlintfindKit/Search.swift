import Foundation

/// Which documents mention these terms — from the index, and from where the index refuses to look.
public enum Search {

    static let readable = ["md", "markdown", "txt"]

    /// Ask Spotlight. Terms AND together, substring, so CJK needs no tokenising and a five-character
    /// phrase matches as a phrase — the thing a word-based index gets wrong.
    ///
    /// No `-onlyin`: the whole index, then filtered here. Spotlight cannot filter by path itself —
    /// `kMDItemPath` returns nothing at the engine level, which is also why pasting a path into the
    /// Spotlight window always finds zero. The filter has to live on this side.
    public static func spotlight(_ terms: [String]) -> [String] {
        guard !terms.isEmpty else { return [] }
        let pred = terms.map { "kMDItemTextContent == '*\($0)*'c" }.joined(separator: " && ")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = [pred]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let lines = String(data: data, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
        return lines.filter { readable.contains(($0 as NSString).pathExtension.lowercased()) && Scope.mine($0) }
    }

    // MARK: - The blind spot

    /// 🔴 SPOTLIGHT DOES NOT INDEX ANYTHING UNDER A DOT-DIRECTORY. Measured 2026-08-05: of the 6967
    /// .md files it knew about on one machine, the number whose path contained a `/.<name>/`
    /// component was ZERO — while `~/.clikae` alone held 6348 and `~/.claude` another 226.
    ///
    /// That is a hole in the one thing this tool claims. "Every markdown file on this machine, no
    /// list to maintain" was false by about 6500 documents, and false in the worst place: what lives
    /// under those directories is an agent's memory and working notes, which is exactly the material
    /// you reach for when you half-remember something. And it failed SILENTLY — "0 files" is
    /// indistinguishable from "that word is nowhere".
    ///
    /// The fix does not try to improve Spotlight. Spotlight is rented; this is ours. And this is a
    /// list of the INDEX's defects, never of anybody's folders, which is what keeps the
    /// no-configuration promise honest: nobody adds their vault to it.
    static func hiddenRoots(home: String) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        return items.filter { $0.hasPrefix(".") }
            .map { (home as NSString).appendingPathComponent($0) }
            .filter { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: $0, isDirectory: &d) && d.boolValue }
    }

    /// Search those places by reading them, since nothing has indexed them.
    ///
    /// 🩸 SYMLINKS ARE FOLLOWED, and that is load-bearing. The memory vault reached through
    /// `~/.clikae` is a symlink, and the first version of this in Python did not follow one — so it
    /// walked 12005 files and found the single document it had been written to find ZERO times. A
    /// fix carrying the same blind spot as the bug is the thing to watch for; only running it
    /// against a known answer showed the difference.
    ///
    /// Following symlinks needs the inode guard, or two names for one directory are walked twice and
    /// a cycle never terminates at all.
    public static func blindSpot(_ terms: [String], home: String = NSHomeDirectory()) -> [String] {
        guard !terms.isEmpty else { return [] }
        let lows = terms.map { $0.lowercased() }
        let fm = FileManager.default
        var found = Set<String>()
        var seen = Set<UInt64>()
        var stack = hiddenRoots(home: home)

        while let dir = stack.popLast() {
            var st = stat()
            guard stat(dir, &st) == 0 else { continue }
            if !seen.insert(UInt64(st.st_ino)).inserted { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                if name == "node_modules" { continue }
                let path = (dir as NSString).appendingPathComponent(name)
                var sub: ObjCBool = false
                // fileExists RESOLVES a symlink, which is exactly what is wanted: a link to a
                // directory has to be descended into, and the inode guard above is what makes that
                // safe rather than infinite.
                guard fm.fileExists(atPath: path, isDirectory: &sub) else { continue }
                if sub.boolValue { stack.append(path); continue }
                guard readable.contains((name as NSString).pathExtension.lowercased()),
                      Scope.mine(path),
                      let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let low = text.lowercased()
                // The RESOLVED path, not the route we arrived by. ~/.clikae reaches one memory
                // directory through more than one symlinked name, so which one a document was
                // reported under came down to walk order — arbitrary, and different between this
                // and the Python engine on the same query. Resolving makes it canonical; the Set
                // makes a document that IS reachable twice appear once.
                if lows.allSatisfy({ low.contains($0) }) {
                    found.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
                }   // AND, as mdfind does
            }
        }
        return found.sorted()
    }

    /// The whole machine: what the index knows, plus what it refuses to look at.
    ///
    /// Indexed results come first, which keeps the common case ordered as it was before the blind
    /// spot was covered. Duplicates cannot happen today — Spotlight has nothing from a
    /// dot-directory — but the dedup stays, because relying on that is relying on the very defect
    /// this works around not being fixed.
    public static func findPaths(_ terms: [String], home: String = NSHomeDirectory()) -> [String] {
        var seen = Set<String>()
        return (spotlight(terms) + blindSpot(terms, home: home)).filter { seen.insert($0).inserted }
    }
}
