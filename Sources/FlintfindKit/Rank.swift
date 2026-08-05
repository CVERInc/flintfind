import Foundation

/// One line worth reading, with the lines either side of it.
public struct Hit: Codable, Sendable, Equatable {
    public let score: Double
    public let path: String
    public let name: String
    public let line: Int
    public let age: Double
    public let text: String
    public let before: String
    public let after: String
}

public struct Passages: Sendable {
    public let hits: [Hit]
    /// Matched, but not on this disk. NAMED rather than silently dropped: the match is real and the
    /// file is yours — it just is not downloaded. Opening one downloads it, and every search after
    /// that includes it.
    public let offline: [String]
    /// How many files were never read because of the cap. A cap the caller cannot see reads as
    /// "that is all there is", so every shell using this has to be able to say so.
    public let skipped: Int
}

public enum Rank {

    // A computed property, not a stored one: a Regex is not Sendable, so a static let would be a
    // shared mutable global under Swift 6 concurrency.
    //
    // 🩸 It used to say building one per call "costs nothing measurable next to reading the file it
    // is about to describe" — and writtenAt does not read the file. The comment reasoned about the
    // wrong function, and the profile disagreed: compiling this was one of the two largest costs
    // left in the run. It is now built ONCE per query and handed down.
    static var dateInName: DateRegex { /(20\d\d)[-\/.](\d{1,2})[-\/.](\d{1,2})/ }
    typealias DateRegex = Regex<(Substring, Substring, Substring, Substring)>
    static let context = 1
    public static let readCap = 250
    static let window = 120

    /// Conversation logs are append-only: mtime says "today" for a line typed months ago, and every
    /// line inherits the same wrong date. The filename knows better when it carries one.
    public static func writtenAt(_ path: String, _ name: String) -> Date {
        writtenAt(path, name, dateInName)
    }

    static func writtenAt(_ path: String, _ name: String, _ re: DateRegex) -> Date {
        if let m = try? re.firstMatch(in: name),
           let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3) {
            var c = DateComponents()
            c.year = y; c.month = mo; c.day = d
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            // An impossible date falls back rather than raising — `strict` is what makes 2026-13-45
            // return nil instead of rolling over into the next year.
            if let date = cal.date(from: c), cal.dateComponents([.year, .month, .day], from: date) == c {
                return date
            }
        }
        // stat, not attributesOfItem: the same mtime without building a dictionary of every other
        // attribute of the file, asked once per candidate.
        var st = stat()
        guard stat(path, &st) == 0 else { return Date() }
        return Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec)
                    + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    /// Rank lines. Reads at most `readCap` files, newest first, and says how many it skipped.
    ///
    /// Ranking has to read; an index only says which files match. On a query matching 846 files that
    /// was 6.5 seconds — the slowest thing this tool has ever done to anyone. Twelve passages get
    /// shown, so reading all 846 buys almost nothing, and a loop you stop reaching for because it is
    /// slow has failed no matter how good the twelfth result was.
    ///
    /// Newest first because the ordering is free: writtenAt reads a filename and an mtime, never the
    /// file itself.
    public static func passages(_ paths: [String], terms: [String], limit: Int = 12) -> Passages {
        let now = Date()
        // 🩸 writtenAt used to be CALLED FROM THE COMPARATOR, so sorting 291 paths asked it about
        // 2400 times — each one compiling a regex and hitting the disk — and then the loop below
        // asked a third time for the age. Once per path, carried through.
        //
        // Sorted by (date desc, original position asc) rather than by date alone: Swift's sort is
        // not GUARANTEED stable and Python's is, so two files sharing a timestamp were free to come
        // out in different orders in the two engines.
        //
        // NOT GATED, and said plainly rather than left looking covered: today's Swift sort happens
        // to be stable, so removing this tiebreak changes no observable answer and no fixture can
        // be built that fails on it. The tiebreak is here to make the guarantee the code's own
        // instead of the standard library's — a check that cannot fail would only be noise.
        let re = dateInName
        let when = paths.map { writtenAt($0, ($0 as NSString).lastPathComponent, re) }
        let ordered = paths.indices
            .sorted { when[$0] == when[$1] ? $0 < $1 : when[$0] > when[$1] }
            .map { paths[$0] }
        let skipped = max(0, ordered.count - readCap)
        var hits: [Hit] = []
        var offline: [String] = []
        let lows = terms.map { $0.lowercased() }

        for path in ordered.prefix(readCap) {
            guard Scope.local(path) else { offline.append(path); continue }
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let base = (path as NSString).lastPathComponent
            let name = (base as NSString).deletingPathExtension
            let lowText = text.lowercased()
            let density = lows.reduce(0) { $0 + lowText.components(separatedBy: $1).count - 1 }
            // Asked again rather than reusing the sort key: the ordering above uses the filename
            // WITH its extension and the age uses the stem, which is what the Python engine does.
            // They disagree only for a name like "notes.2026-08-05" — matching it costs one stat.
            let age = max(0, now.timeIntervalSince(writtenAt(path, name, re)) / 86400)
            let lines = text.components(separatedBy: "\n")
            let lowName = name.lowercased()

            for (i, line) in lines.enumerated() {
                let low = line.lowercased()
                let n = lows.filter { low.contains($0) }.count
                if n == 0 { continue }
                var score = Double(n) * 4.0                                                   // all your terms on one line
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { score += 3.0 }   // a heading names the topic
                if lows.contains(where: { lowName.contains($0) }) { score += 2.0 }
                score += Double(min(density, 8)) * 0.25
                score += 2.0 / (1.0 + age / 90.0)
                hits.append(Hit(
                    score: score, path: path, name: name, line: i + 1, age: age,
                    text: line.trimmingCharacters(in: .whitespaces),
                    before: (i > 0 && context > 0) ? lines[i - 1].trimmingCharacters(in: .whitespaces) : "",
                    after: (i + 1 < lines.count && context > 0) ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""))
            }
        }
        // Stable by design: equal scores keep the order they were found in, which is what makes a
        // heading's +3 the ONLY reason it can overtake a line that was already ahead of it.
        let top = hits.enumerated().sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
        return Passages(hits: top.prefix(limit).map(\.element), offline: offline, skipped: skipped)
    }

    /// Of the passages that mention either term, what share mention both.
    ///
    /// A window is a neighbourhood; a file is a filing cabinet. Measured over one real corpus, a
    /// pair of terms that are NOT about each other shared a file 14% of the time and a window 0% of
    /// the time, while a genuine neighbour held up under both. This is the only measure in this
    /// engine that survived that test.
    public static func windowOverlap(_ paths: [String], _ a: String, _ b: String) -> Double {
        let la = a.lowercased(), lb = b.lowercased()
        var winA = 0, winBoth = 0
        for p in paths {
            guard Scope.local(p),   // same reason as passages(): reading a cloud placeholder is a download
                  let text = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n")
            var i = 0
            while i < lines.count {
                let w = lines[i..<min(i + window, lines.count)].joined(separator: "\n").lowercased()
                let inA = w.contains(la), inB = w.contains(lb)
                if inA || inB {
                    winA += 1
                    if inA && inB { winBoth += 1 }
                }
                i += window
            }
        }
        return Double(winBoth) / Double(max(winA, 1))
    }
}
