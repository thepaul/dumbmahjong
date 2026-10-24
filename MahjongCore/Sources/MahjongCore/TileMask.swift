/// A set of tile indices within a layout, stored as a bitset. Used for "which
/// tiles are still on the board"; cheap to copy and hash.
public struct TileMask: Hashable, Sendable {
    public let count: Int
    private var words: [UInt64]

    /// A mask over `count` tiles, either all present or all absent.
    public init(count: Int, allPresent: Bool) {
        self.count = count
        let wordCount = (count + 63) / 64
        words = Array(repeating: 0, count: wordCount)
        if allPresent {
            for i in 0..<count {
                insert(i)
            }
        }
    }

    public subscript(index: Int) -> Bool {
        words[index >> 6] & (1 << UInt64(index & 63)) != 0
    }

    public mutating func insert(_ index: Int) {
        words[index >> 6] |= 1 << UInt64(index & 63)
    }

    public mutating func remove(_ index: Int) {
        words[index >> 6] &= ~(1 << UInt64(index & 63))
    }

    public var isEmpty: Bool { words.allSatisfy { $0 == 0 } }

    public var presentCount: Int { words.reduce(0) { $0 + $1.nonzeroBitCount } }
}
