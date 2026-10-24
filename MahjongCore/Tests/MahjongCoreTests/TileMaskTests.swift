import MahjongCore
import Testing

@Test func tileMaskBasics() {
    var mask = TileMask(count: 144, allPresent: true)
    #expect(mask.presentCount == 144)
    #expect(mask[0] && mask[63] && mask[64] && mask[143])
    mask.remove(64)
    #expect(!mask[64])
    #expect(mask.presentCount == 143)
    mask.insert(64)
    #expect(mask == TileMask(count: 144, allPresent: true))
    #expect(TileMask(count: 144, allPresent: false).isEmpty)
}
