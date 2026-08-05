import FlintfindKit
import Foundation

// flintfind — guess, confirm, adjust. A search loop for your own writing.
//
// Struck like flint: every strike costs nothing, most produce nothing, one catches. `ff` is the
// command; flintfind is the thing.
//
// This file decides how an answer LOOKS. Everything deciding what it IS lives in FlintfindKit, so
// marktile's editor can open a second door onto the same engine without a second copy of it.

let usage = """
flintfind — guess, confirm, adjust. A search loop for your own writing.

The research this came from ended at a wall and an open door. The wall: a rare coined term cannot be
*discovered* by any frequency or association measure, because until it is named it is
indistinguishable from noise. The door: once named, confirming it takes under half a second.

So this tool does not guess. It makes guessing free.

    ff 天地                  what surrounds this, ranked, as passages you can read
    ff 天地 玄黃             are these the same thread? — and the passages where both appear
    ff parser markdown swift as many terms as you like; they AND
    ff "the exact phrase"    quote it and the words have to be adjacent
    ff --json [--stream] x   the same answer, shaped for a program

Chinese needs no quotes — it matches as a substring already, so 「天地玄黃」 is one word to this
tool. Only spaces need rescuing.

Every line it prints was written by you, so there is nothing here that can be invented.
"""

struct Answer: Codable {
    let query: [String], files: Int, unindexed: Int, skipped: Int
    let offline: [String], hits: [Hit], partial: Bool
}

let D = Terminal.dim, B = Terminal.bold, C = Terminal.cyan
let Y = Terminal.yellow, G = Terminal.green, R = Terminal.reset

let argv = Array(CommandLine.arguments.dropFirst())
guard !argv.isEmpty else { print(usage); exit(0) }

let wantsJSON = argv.contains("--json")
let wantsStream = argv.contains("--stream")
let terms = argv.filter { $0 != "--json" && $0 != "--stream" }
guard !terms.isEmpty else { exit(0) }

let started = Date()

// ── the machine-readable door ───────────────────────────────────────────────────────────────────
// JSON is a rendering, exactly as colour and OSC 8 are renderings, so it belongs here and not in
// the engine. One object per line under --stream: the indexed half is printed the moment it is
// known and the rest ~4s later, because covering what nothing has indexed means opening the files.
if wantsJSON {
    func emit(_ paths: [String], unindexed: Int, partial: Bool) {
        let r = Rank.passages(paths, terms: terms)
        let a = Answer(query: terms, files: paths.count, unindexed: unindexed, skipped: r.skipped,
                       offline: r.offline, hits: r.hits, partial: partial)
        if let d = try? JSONEncoder().encode(a), let s = String(data: d, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
    }
    let indexed = Search.spotlight(terms)
    if wantsStream { emit(indexed, unindexed: 0, partial: true) }
    let blind = Search.blindSpot(terms)
    var seen = Set<String>()
    let all = (indexed + blind).filter { seen.insert($0).inserted }
    emit(all, unindexed: blind.count, partial: false)
    exit(0)
}

// ── the human door ──────────────────────────────────────────────────────────────────────────────
var paths: [String] = []
var unindexed = 0

if terms.count == 2 {
    // One call per term, and the intersection IS the AND — a third query for the same answer is the
    // difference between a loop you keep using and one you stop reaching for.
    let a = Set(Search.findPaths([terms[0]])), b = Set(Search.findPaths([terms[1]]))
    let both = a.intersection(b)
    // Sharing a FILE proves almost nothing: a 17,000-line append-only log puts every subject next to
    // every other, and lift cannot tell that apart — measured on one real corpus it scored a
    // technical term against an unrelated everyday word at 29×, and against that term's own English
    // twin at only 14×. Sharing a 120-line WINDOW is what separates a real pairing from two things
    // merely filed together, and the overlap is a handful of files, so it costs nothing to check.
    let near = Rank.windowOverlap(both.sorted(), terms[0], terms[1])
    let verdict = near >= 0.25 ? "\(G)same thread\(R)" : near >= 0.08 ? "\(Y)related\(R)" : "\(D)probably not\(R)"
    let pct = Int((near * 100).rounded())
    print("\n  \(B)\(terms[0])\(R) ↔ \(B)\(terms[1])\(R)   \(verdict)  "
          + "\(D)\(pct)% of the passages that mention one mention both\(R)")
    print("  \(D)\(terms[0]): \(a.count) files · \(terms[1]): \(b.count) files · both: \(both.count)\(R)")
    paths = both.sorted()
} else {
    let indexed = Search.spotlight(terms)
    let blind = Search.blindSpot(terms)
    unindexed = blind.count
    var seen = Set<String>()
    paths = (indexed + blind).filter { seen.insert($0).inserted }
}

// Offered BEFORE the results, not after: an escape hatch printed below twelve passages is one the
// reader has already scrolled past by the time they decide the answer was wrong.
if terms.count > 1 && paths.count > 120 {
    let phrase = terms.joined(separator: " ")
    let n = Search.spotlight([phrase]).count
    if n > 0 && n < Int(Double(paths.count) * 0.7) {
        print("\n  \(Y)\(n) files contain the exact phrase\(R) \(D)— ff \"\(phrase)\"\(R)")
    }
}

let result = Rank.passages(paths, terms: terms)
let elapsed = Date().timeIntervalSince(started)
// Say how many came from where the index cannot look. The failure this covers was SILENT — "0 files"
// read exactly like "that word is nowhere" — so the fix has to be visible, or the next person has no
// reason to believe the number in front of them.
let blindNote = unindexed > 0 ? " · \(G)\(unindexed) beyond the index\(R)" : ""
let cap = result.skipped > 0 ? " · \(Y)read the \(Rank.readCap) newest of \(paths.count)\(R)" : ""
print("\n  \(D)\(paths.count) files · \(result.hits.count) shown · \(String(format: "%.2f", elapsed))s\(R)\(blindNote)\(cap)\n")

for h in result.hits {
    let loc = "\(String(h.name.prefix(38))):\(h.line)"
    let pad = String(repeating: " ", count: max(0, 44 - loc.count))
    print("  \(C)\(loc)\(pad)\(R)\(D)\(String(format: "%5.0f", h.age))d\(R)")
    if !h.before.isEmpty { print("    \(D)\(String(h.before.prefix(100)))\(R)") }
    print("    \(String(h.text.prefix(110)))")
    if !h.after.isEmpty { print("    \(D)\(String(h.after.prefix(100)))\(R)") }
    print("    \(D)\(Terminal.link(h.path))\(R)\n")
}

if !result.offline.isEmpty {
    // Named, not silently dropped: the match is real and the file is yours — it just is not on this
    // disk yet. Opening it downloads it, and every search after that includes it.
    print("  \(Y)\(result.offline.count) more in the cloud, not downloaded\(R) "
          + "\(D)(open one and it joins the next search)\(R)")
    for p in result.offline.prefix(3) { print("    \(D)\(Terminal.link(p))\(R)") }
    print("")
}
if result.hits.isEmpty {
    print("  \(D)nothing. try one term, or a different guess — that is the loop.\(R)\n")
}
Terminal.log(terms: terms, files: paths.count, shown: result.hits.count, seconds: elapsed)
