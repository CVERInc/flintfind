import Foundation

/// What counts as a document, and whether it is actually here.
///
/// Ported from ffcore.py, where the same two rules are enforced by regular expressions. They are
/// written out as prefix and substring tests instead: both patterns are anchored lists of literals,
/// a regex was never buying anything, and the rule reads as what it is.
public enum Scope {

    // MARK: - mine

    /// Directories that belong to the system rather than to a person. Anchored at the ROOT: the
    /// user's own `~/Library` holds iCloud and Google Drive, where 700+ of their documents live, so
    /// a rule matching `/Library/` anywhere would throw away the largest single group of real work.
    /// 114 files here — CommandLineTools, a JDK, Ruby's docs.
    static let systemRoots = ["/Library/", "/System/", "/usr/", "/bin/", "/sbin/",
                              "/etc/", "/var/", "/opt/", "/private/", "/Applications/"]

    /// An app's own files, wherever the app put them. 222 on the machine this was measured on, and
    /// NONE of the 6231 documents in that machine's iCloud and Google Drive. This is the rule that
    /// keeps a password-strength wordlist — Codex ships english_wikipedia.txt — out of the results
    /// for every English word you will ever search for, and drops Google Drive's second, cached
    /// copy of files you already have.
    static let appData = ["/Library/Application Support/", "/Library/Caches/",
                          "/Library/Containers/", "/Library/Group Containers/",
                          "/Library/Developer/"]

    /// 2156 of the 2166 vendored files on the machine this was measured on. Everything else a
    /// broader rule would catch is in single digits — /dist/ 13, site-packages 7, vendor 4 — and a
    /// rule for /build/ or /dist/ would one day hide a folder somebody actually named that.
    static let vendored = "/node_modules/"

    /// Written by a person, on purpose. The one distinction worth drawing over a whole disk.
    ///
    /// 🔴 The line this rule is allowed to draw is machine-generated versus written by a person —
    /// never WHOSE writing it is. Another person's vault under `~/Documents` is as much a document
    /// as anything else here.
    public static func mine(_ path: String) -> Bool {
        if path.contains(vendored) { return false }
        if systemRoots.contains(where: { path.hasPrefix($0) }) { return false }
        if appData.contains(where: { path.contains($0) }) { return false }
        return true
    }

    // MARK: - local

    /// The flag the system sets on a file whose bytes are not here.
    static let dataless: UInt32 = 0x4000_0000   // SF_DATALESS

    /// Is this file actually ON this disk?
    ///
    /// Searching the whole machine reaches iCloud Drive and Google Drive, and a file that lives
    /// there may be an index entry with no bytes behind it. The content is indexed — the search
    /// matched it honestly — but opening one is a synchronous download. Measured once: a search
    /// that touched about thirty never-downloaded files in a second vault took 61.89 SECONDS, and
    /// 0.57s on the next run. A tool whose whole premise is that guessing is free cannot have a
    /// first guess that costs a minute, so these are NAMED in the result instead of being read.
    ///
    /// Two signals, because they disagree: `SF_DATALESS` is the flag the system sets, and zero
    /// blocks with a nonzero size is what a placeholder looks like when the flag has not been set.
    public static func local(_ path: String) -> Bool {
        var st = stat()
        guard stat(path, &st) == 0 else { return false }
        if st.st_flags & dataless != 0 { return false }
        return !(st.st_blocks == 0 && st.st_size > 0)
    }
}
