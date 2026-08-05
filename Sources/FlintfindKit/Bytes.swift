import Foundation

/// Literal substring matching, over UTF-8 bytes.
///
/// 🩸 `String.contains(_:)` IS NOT THE FAST PATH. It resolves to Foundation's
/// `range(of:options:range:locale:)`, which does canonical-equivalence matching and steps the
/// haystack one grapheme cluster at a time. Sampled on one real corpus it was 2255 of 6231 main
/// thread samples — 36% of the entire run — and the profile was wall-to-wall
/// `_opaqueComplexCharacterStride` and Unicode table lookups. CJK is its worst case: every
/// character is a separate cluster decision.
///
/// Matching bytes is not only faster, it is CLOSER TO CORRECT here. `in` on a Python str is exact
/// code points, never canonical equivalence, and the Python engine is the reference this port is
/// checked against — so a composed é and a decomposed é are two different things to it. Foundation
/// called them equal. This removes a divergence rather than introducing one.
public enum Bytes {

    /// Fold ASCII A–Z to a–z and leave every other byte alone. Continuation bytes of a multi-byte
    /// scalar are all ≥ 0x80, so they can never be mistaken for an ASCII letter — folding a UTF-8
    /// stream byte by byte is safe without decoding it.
    static let fold: [UInt8] = (UInt8(0)...UInt8(255)).map { b -> UInt8 in
        let isUpper: Bool = b >= 65 && b <= 90
        return isUpper ? b &+ 32 : b
    }

    /// The two exceptions, MEASURED rather than remembered.
    ///
    /// Of every scalar at or above U+0080, exactly two lowercase into something containing an ASCII
    /// letter: U+0130 LATIN CAPITAL LETTER I WITH DOT ABOVE → "i" + U+0307, and U+212A KELVIN SIGN
    /// → "k". Everything else that lowers to ASCII already WAS that ASCII letter. That is what makes
    /// byte-level ASCII folding exact instead of approximate — and the selftest re-runs the scan, so
    /// a future Unicode revision adding a third one fails the gate rather than quietly changing an
    /// answer.
    static let dottedCapitalI: [UInt8] = [0xC4, 0xB0]   // U+0130
    static let kelvinSign: [UInt8] = [0xE2, 0x84, 0xAA] // U+212A

    /// A search term, prepared once per query rather than once per file: the same handful of terms
    /// is asked about eleven thousand times.
    public struct Needle: Sendable {
        public let bytes: [UInt8]
        /// True when byte-level ASCII folding answers this needle exactly.
        ///
        /// False as soon as the term contains a CASED non-ASCII character — 'é', 'ß', 'я' — because
        /// then the text may hold 'É', 'ẞ', 'Я', which only full Unicode lowering brings together.
        /// Those terms take the slow path and are correct there; CJK, digits and punctuation are
        /// uncased, so a Chinese query is exact on the fast path.
        public let foldable: Bool
        /// Whether the two exceptions above could possibly matter for this term.
        public let watchExotic: Bool

        public init(_ term: String) {
            let low = term.lowercased()
            bytes = Array(low.utf8)
            foldable = low.unicodeScalars.allSatisfy { $0.isASCII || !$0.properties.isCased }
            watchExotic = low.utf8.contains(where: { $0 == UInt8(ascii: "i") || $0 == UInt8(ascii: "k") })
        }
    }

    public static func needles(_ terms: [String]) -> [Needle] { terms.map(Needle.init) }

    /// Can this whole query be answered on raw bytes.
    public static func foldable(_ needles: [Needle]) -> Bool { needles.allSatisfy(\.foldable) }

    // MARK: - Raw bytes

    /// Find `needle` in `hay`, folding ASCII case in the haystack. The needle is already lowercase.
    ///
    /// When the needle's first byte is not an ASCII letter — every CJK term — there is only one byte
    /// to look for, so `memchr` does the scanning and this loop only confirms. That is the case this
    /// tool is used in most.
    static func find(_ hay: UnsafeRawBufferPointer, _ needle: [UInt8], from: Int) -> Int? {
        let m = needle.count, n = hay.count
        guard m > 0, n >= m else { return m == 0 ? from : nil }
        let base = hay.baseAddress!
        let first = needle[0]
        let upper: UInt8? = (first >= 97 && first <= 122) ? first - 32 : nil
        var i = from
        return needle.withUnsafeBufferPointer { np -> Int? in
            let nb = np.baseAddress!
            while i + m <= n {
                if upper == nil {
                    // One candidate byte: let libc find it.
                    guard let at = memchr(base + i, Int32(first), n - i) else { return nil }
                    i = UnsafeRawPointer(at) - base
                    if i + m > n { return nil }
                } else {
                    while i + m <= n {
                        let b = base.load(fromByteOffset: i, as: UInt8.self)
                        if b == first || b == upper! { break }
                        i += 1
                    }
                    if i + m > n { return nil }
                }
                var k = 1
                while k < m, fold[Int(base.load(fromByteOffset: i + k, as: UInt8.self))] == nb[k] { k += 1 }
                if k == m { return i }
                i += 1
            }
            return nil
        }
    }

    /// Does this buffer contain every needle. Callers must have checked `foldable(_:)` first.
    public static func containsAll(_ hay: UnsafeRawBufferPointer, _ needles: [Needle]) -> Bool {
        for n in needles where !n.bytes.isEmpty {
            if find(hay, n.bytes, from: 0) == nil { return false }
        }
        return true
    }

    /// Whether either measured exception is physically present, in which case the fast path has to
    /// stand aside for this file. Asked only when a term contains an i or a k, and in years of this
    /// corpus it has never fired — but a rule you cannot state the exception to is a guess.
    public static func holdsExotic(_ hay: UnsafeRawBufferPointer) -> Bool {
        find(hay, dottedCapitalI, from: 0) != nil || find(hay, kelvinSign, from: 0) != nil
    }

    // MARK: - Strings

    /// The same question about an already-lowercased String. Used where the text is in hand anyway.
    public static func contains(_ hay: String, _ n: Needle) -> Bool {
        guard !n.bytes.isEmpty else { return true }
        var h = hay
        return h.withUTF8 { buf in
            n.bytes.withUnsafeBufferPointer {
                memmem(buf.baseAddress, buf.count, $0.baseAddress!, n.bytes.count) != nil
            }
        }
    }

    /// How many times this needle appears — NON-OVERLAPPING, because that is what
    /// `components(separatedBy:).count - 1` counted before this existed, and the density score is
    /// calibrated against those numbers.
    public static func count(_ hay: String, _ n: Needle) -> Int {
        guard !n.bytes.isEmpty else { return 0 }
        var h = hay
        return h.withUTF8 { buf in
            guard var base = UnsafeRawPointer(buf.baseAddress) else { return 0 }
            var left = buf.count, found = 0
            n.bytes.withUnsafeBufferPointer { np in
                let nb = np.baseAddress!, nn = n.bytes.count
                while left >= nn, let at = memmem(base, left, nb, nn) {
                    found += 1
                    let step = UnsafeRawPointer(at) - base + nn
                    base += step
                    left -= step
                }
            }
            return found
        }
    }
}
