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

print("")
if failures.isEmpty {
    print("✅ flintfind selftest: all pass")
} else {
    print("✗ flintfind selftest: \(failures.count) failed")
    try? FileManager.default.removeItem(at: dir)
    exit(1)
}
