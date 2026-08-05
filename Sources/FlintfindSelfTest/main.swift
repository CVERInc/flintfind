import FlintfindKit
import Foundation

// The Python gate, carried across. Run it: `swift run flintfind-selftest`.
//
// WHAT A PORT MUST NOT DO is arrive with a fresh set of expectations — then it proves the new code
// agrees with itself, which is the one thing nobody doubted. Every value below is the value
// test_ff.py already asserted, and the two gates are meant to disagree loudly if the port drifted.
//
// An executable rather than a testTarget because this machine has Command Line Tools and no Xcode,
// so XCTest does not exist here and `swift test` cannot run at all. reepub ships ReepubSelfTest the
// same way. `python3 test_ff.py` and this are the same gesture.
//
// The CJK is public domain (千字文): a fixture that never touches a multi-byte, space-free term
// proves nothing about a tool whose whole trick is substring matching — and which words a real
// person searches for is about that person, which is not a fixture's business.

var failures: [String] = []

@MainActor
func check(_ got: Bool, _ why: String) {
    if got {
        print("PASS \(why)")
    } else {
        failures.append(why)
        print("FAIL \(why)")
    }
}

let home = NSHomeDirectory()

// ── mine: written by a person, on purpose ───────────────────────────────────────────────────────
check(Scope.mine("\(home)/Developer/tile-oss/README.md"), "mine: a repo's own document")
// Under ~/Library and NOT excluded — 700+ real documents live there, which is why the system rule is
// anchored at the ROOT instead of matching /Library/ anywhere.
check(Scope.mine("\(home)/Library/Mobile Documents/com~apple~CloudDocs/notes/2026-08.md"),
      "mine: iCloud Drive")
check(Scope.mine("\(home)/Library/CloudStorage/GoogleDrive-x/My Drive/plan.md"), "mine: Google Drive")
check(!Scope.mine("\(home)/Developer/reef/node_modules/marked/README.md"),
      "mine: a vendored dependency is not mine")
check(!Scope.mine("/Library/Developer/CommandLineTools/usr/share/doc/note.md"),
      "mine: a system path, anchored at the ROOT")
check(!Scope.mine("/Applications/Xcode.app/Contents/README.md"), "mine: inside an app bundle")
check(!Scope.mine("\(home)/Library/Application Support/Codex/english_wikipedia.txt"),
      "mine: an app's own data, wherever the app put it")
check(!Scope.mine("\(home)/Library/Caches/something/cached.md"), "mine: a cache")
check(!Scope.mine("\(home)/Library/Containers/com.example/Data/note.md"), "mine: a container")
// 🔴 The line this rule may draw is machine-generated versus written by a person — never WHOSE.
check(Scope.mine("\(home)/Documents/AnotherPersonsVault/宇宙洪荒/2026-01-01.md"),
      "mine: another person's notes are still documents — the line is never about WHOSE")

// ── local: is the file actually on this disk ────────────────────────────────────────────────────
// 🩸 The fixture lives under the REAL home, not in a temporary directory. macOS puts those under
// /var/folders — that is /private/var/folders — and BOTH prefixes are in the system list, so a
// fixture built there is rejected before it is ever read. The Python gate learned this by watching
// two assertions return nothing while saying nothing about the code.
let dir = URL(fileURLWithPath: home).appendingPathComponent(".fftest-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }

let present = dir.appendingPathComponent("here.md")
try? "bytes".write(to: present, atomically: true, encoding: .utf8)
check(Scope.local(present.path), "local: a file with bytes on the disk")
check(!Scope.local(dir.appendingPathComponent("missing.md").path), "local: a path that does not exist")

// 🩸 A SPARSE file has a nonzero size and zero blocks — which is exactly the shape of a cloud
// placeholder whose flag has not been set, and exactly why local() carries a second signal at all.
// "Cannot be synthesised on a local disk" was written about this branch and was half wrong; a
// mutation deleting it left the gate green, which is what sent me back to re-ask.
let sparse = dir.appendingPathComponent("sparse.md")
FileManager.default.createFile(atPath: sparse.path, contents: nil)
if let fh = try? FileHandle(forWritingTo: sparse) {
    try? fh.truncate(atOffset: 4096)
    try? fh.close()
}
check(!Scope.local(sparse.path),
      "local: nonzero size with zero blocks is a placeholder, flag or no flag")

// NOT COVERED, said out loud rather than left looking like coverage: the SF_DATALESS flag READ. The
// system sets that flag and this cannot; its sibling signal above is what is proven.

// ── blindSpot: the documents Spotlight refuses to look at ───────────────────────────────────────
// 🩸 THE SYMLINK CASE IS THE ONE THAT MATTERS, and this gate did not have it at all until
// 2026-08-05. The Python gate asserted both halves; the port arrived carrying neither, and nothing
// said so, because a missing test looks exactly like a passing one.
//
// What that cost, measured: an optimisation swapping `fileExists(atPath:isDirectory:)` for
// `contentsOfDirectory(at:includingPropertiesForKeys: [.isDirectoryKey])` stopped descending into
// the symlinked vault. Real answers fell from 291 files to 165 — and this gate printed "all pass"
// through the whole thing. That is the same blind spot the code below is written to cover, arriving
// for the third time, which is why it is now asserted rather than described.

func tree(_ tag: String) -> URL {
    let d = URL(fileURLWithPath: home).appendingPathComponent(".fftest-\(tag)-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

func put(_ root: URL, _ rel: String, _ body: String) {
    let f = root.appendingPathComponent(rel)
    try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try? body.write(to: f, atomically: true, encoding: .utf8)
}

func under(_ root: URL, _ paths: [String]) -> [String] {
    paths.map { $0.replacingOccurrences(of: root.path + "/", with: "") }.sorted()
}

let t1 = tree("blind")
put(t1, ".agent/notes/plain.md", "a note about 天地 here\n")
put(t1, "vault-real/linked.md", "another note about 天地\n")   // NOT hidden, NOT under a dot-dir
try? FileManager.default.createSymbolicLink(atPath: t1.appendingPathComponent(".agent/vault").path,
                                            withDestinationPath: t1.appendingPathComponent("vault-real").path)
put(t1, ".agent/notes/other.md", "nothing relevant\n")
put(t1, ".agent/node_modules/pkg/README.md", "天地 in a dependency\n")
// 🩸 These two exist because a mutation run showed that deleting the extension filter and deleting
// the mine() call BOTH left the Python gate green: nothing in the fixture was a non-markdown file
// that matched, and node_modules is pruned before mine() is ever asked. Each reaches exactly one.
put(t1, ".agent/notes/manual.pdf", "天地 in a pdf\n")
put(t1, ".agent/Library/Caches/cached.md", "天地 in an app cache\n")

// 🩸 The second path is "vault-real/linked.md", NOT ".agent/vault/linked.md": results are the
// RESOLVED path, not the route walked to reach them. ~/.clikae reaches one memory directory through
// several symlinked names, so which name a document appeared under came down to walk order —
// arbitrary, and demonstrably different between this engine and the Python one on the same query.
check(under(t1, Search.blindSpot(["天地"], home: t1.path))
        == [".agent/notes/plain.md", "vault-real/linked.md"],
      "blindSpot: reads inside a dot-directory AND follows a symlink out of one, reporting the "
      + "RESOLVED path, skipping non-matches and vendored files")
try? FileManager.default.removeItem(at: t1)

// A cycle has to terminate rather than walk for ever — the price of following links at all.
let t2 = tree("loop")
put(t2, ".loop/inner/note.md", "天地\n")
try? FileManager.default.createSymbolicLink(atPath: t2.appendingPathComponent(".loop/inner/back").path,
                                            withDestinationPath: t2.appendingPathComponent(".loop").path)
check(under(t2, Search.blindSpot(["天地"], home: t2.path)) == [".loop/inner/note.md"],
      "blindSpot: a symlink cycle terminates, and counts once")
try? FileManager.default.removeItem(at: t2)

// 🩸 The one file on which bytes and Unicode genuinely disagree. "TÜRKİYE" holds no ASCII i at all,
// yet lowering it yields "türki̇ye", which does — so the reference engine finds it when asked for
// "i" and a byte scan cannot. This is the whole reason the fast path carries an exception, and
// without this fixture that exception is a paragraph nobody can check.
let t3 = tree("exotic")
put(t3, ".notes/turkish.md", "TÜRKİYE\n")
check(under(t3, Search.blindSpot(["i"], home: t3.path)) == [".notes/turkish.md"],
      "blindSpot: U+0130 lowers into an ASCII i, and the byte path stands aside for the file holding it")
try? FileManager.default.removeItem(at: t3)

// ── Bytes: the fast path has to be exact, not nearly ────────────────────────────────────────────
// The whole justification for matching raw bytes is that ASCII folding gives the SAME answer as
// lowering both sides, and that rests on one claim about Unicode. Claims about Unicode do not
// belong in a comment.
var lowersIntoASCII: [UInt32] = []
for v in UInt32(0x80)...UInt32(0x10FFFF) {
    guard let s = Unicode.Scalar(v) else { continue }
    if String(s).lowercased().unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) {
        lowersIntoASCII.append(v)
    }
}
// U+0130 LATIN CAPITAL LETTER I WITH DOT ABOVE → "i" + U+0307, and U+212A KELVIN SIGN → "k".
// Everything else that lowercases to an ASCII letter already WAS that letter. If a future Unicode
// revision adds a third, this fails here rather than quietly returning a wrong answer for a file
// nobody thought to check.
check(lowersIntoASCII == [0x0130, 0x212A],
      "Bytes: exactly two scalars above ASCII lower into an ASCII letter — the fast path's premise")

check(Bytes.foldable(Bytes.needles(["天地", "parser", "TODO-2026"])),
      "Bytes: CJK, ASCII and digits need no Unicode lowering")
check(!Bytes.foldable(Bytes.needles(["café"])),
      "Bytes: a cased non-ASCII term stands aside — 'É' only meets 'é' through full lowering")

func has(_ hay: String, _ term: String) -> Bool {
    var h = hay
    return h.withUTF8 { Bytes.containsAll(UnsafeRawBufferPointer($0), Bytes.needles([term])) }
}
check(has("千字文 天地玄黃 宇宙洪荒", "天地"), "Bytes: a CJK substring, no tokenising")
check(has("The QUICK brown", "quick"), "Bytes: ASCII case folds in the haystack")
check(!has("天地", "玄黃"), "Bytes: a term that is not there")
check(has("anything", ""), "Bytes: an empty term is contained by everything, as `\"\" in s` is")
// 🩸 Bytes, not Characters: a needle can start mid-scalar only if the search is byte-blind, and
// this is the case that would catch it — the second byte of 天 (U+5929 → E5 A4 A9) can never be
// mistaken for the start of anything, because continuation bytes are all ≥ 0x80 and ASCII is not.
check(!has("天", "\u{0}"), "Bytes: a NUL needle does not match a multi-byte character's insides")

check(Search.readableName("note.md") && Search.readableName("NOTE.MD")
      && Search.readableName("a.markdown") && Search.readableName("b.txt"),
      "readableName: the three extensions, either case")
check(Search.readableName(".md"),
      "readableName: `endswith` counts a file named exactly \".md\" — the Python engine's answer")
check(!Search.readableName("manual.pdf") && !Search.readableName("mdfile"),
      "readableName: not a near miss, not a suffix without the dot")

print("")
if failures.isEmpty {
    print("✅ flintfind selftest: all pass")
} else {
    print("✗ flintfind selftest: \(failures.count) failed")
    try? FileManager.default.removeItem(at: dir)
    exit(1)
}
