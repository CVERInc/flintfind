# flintfind

> Guess, confirm, adjust. A search loop for your own writing — every markdown file on your Mac, including the ones Spotlight refuses to index, with the passages already on screen. `ff` is the command; flintfind is the thing.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)](https://swift.org)

**No network · No telemetry · No index to build · Nothing to configure.**

---

## Why flintfind?

Struck like flint: every strike costs nothing, most produce nothing, one catches.
That is the whole design. This tool does not try to guess what you meant — it
makes guessing so cheap that you can afford to be wrong four times in a row.

It came out of a piece of research that ended at a wall and an open door. The
wall: a rare coined term cannot be *discovered* by any frequency or association
measure, because until it is named it is indistinguishable from noise. The open
door: once you name it, confirming it takes under half a second. So the loop is
yours, and the machine's job is to make each turn of it free.

- **The whole machine, no list to maintain.** There is no vault to register, no
  folder to add, no index to rebuild. Point it at nothing; it searches
  everything you wrote.
- **🔴 It covers Spotlight's blind spot.** Spotlight does not index anything
  under a dot-directory. On one machine, of the 6967 markdown files it knew
  about, the number whose path contained a `/.name/` component was **zero** —
  while a single agent's memory directory held 6348 of them. flintfind walks
  those itself, and says how many results came from there. The failure this
  covers was silent: "0 files" reads exactly like "that word is nowhere".
- **Passages, not filenames.** A list of paths is a second search. Every result
  is the matching line with the lines either side of it, ranked, ready to read.
- **CJK needs no quoting.** Terms match as substrings, so 「天地玄黃」 is one word
  to this tool. Only spaces need rescuing, with quotes.
- **It never asks whose writing something is.** The one line it draws is
  machine-generated versus written by a person — a vendored dependency and an
  app's own cached wordlist are out; somebody else's notes on your disk are in.
- **It will not download your cloud files behind your back.** A match in iCloud
  or Google Drive that has no bytes on this disk is *named*, never opened —
  reading one is a synchronous download, and a search that costs a minute is a
  loop you stop reaching for.

## Install

```sh
git clone https://github.com/CVERInc/flintfind.git
cd flintfind
swift build -c release
cp .build/release/ff /usr/local/bin/
```

## Use

```
ff 天地                     what surrounds this, ranked, as passages you can read
ff 天地 玄黃                are these the same thread? — and the passages where both appear
ff parser markdown swift    as many terms as you like; they AND
ff "the exact phrase"       quote it and the words have to be adjacent
ff --json [--stream] x      the same answer, shaped for a program
```

Two terms answer a different question from one. Sharing a *file* proves almost
nothing — a 17,000-line append-only log puts every subject next to every other —
so a pair is scored on how often they share a 120-line **window**. Measured on
one real corpus, a technical term scored 29× against an unrelated everyday word
by file, and 0% by window. The window is the measure that survived.

## As a library

`FlintfindKit` is the engine; the `ff` command is one shell over it. An editor
or an app can open a second door onto the same engine without carrying a second
copy of it.

```swift
.package(url: "https://github.com/CVERInc/flintfind.git", from: "0.1.0")
```

```swift
import FlintfindKit

let paths = Search.findPaths(["天地"])          // the index, plus its blind spot
let result = Rank.passages(paths, terms: ["天地"])
for hit in result.hits { print(hit.path, hit.line, hit.text) }
```

## Speed

Searching without an index means reading, so the work is real: about 11,500
files and 120 MB on the machine this was tuned on, in **1.9 seconds** cold, for
a query matching 291 documents.

Getting there took four rounds of sampling, and the lesson each time was the
same — the previous fix moves the bottleneck, so the old profile is a ruler
measuring something else:

| | cost | why |
|---|---|---|
| `String.contains` | 36% | it is Foundation's `range(of:)` — canonical-equivalence matching, one grapheme cluster at a time |
| decode + `lowercased()` | 71% | building a `String` out of every file to answer yes or no |
| `contentsOfDirectory` | 50% of what was left | an `NSString` per entry, across 11,500 of them |
| `writtenAt` | the rest | it was being called **from inside a sort comparator** |

Matching UTF-8 bytes rather than `String` is not only faster, it is closer to
correct here: `in` on a Python str is exact code points, never canonical
equivalence, and the Python reference implementation is what this is checked
against. The byte path is exact rather than approximate — a scan of every
Unicode scalar shows exactly two above ASCII that lowercase into an ASCII
letter (U+0130 and U+212A), and a term carrying a cased non-ASCII character
takes the slower, fully-Unicode path. The self-test re-runs that scan, so a
future Unicode revision fails the build instead of quietly changing an answer.

## Testing

```sh
swift run flintfind-selftest
```

An executable rather than an XCTest target, so it runs on a machine that has
Command Line Tools and no Xcode. Every expectation in it is a value the Python
reference gate already asserted — a port that arrives with a fresh set of
expectations only proves the new code agrees with itself, which is the one
thing nobody doubted.

The CJK fixtures are public domain (千字文): a fixture that never touches a
multi-byte, space-free term proves nothing about a tool whose whole trick is
substring matching — and which words a real person searches for is about that
person, which is not a fixture's business.

## Licence

MIT © 2026 CVER Inc.
