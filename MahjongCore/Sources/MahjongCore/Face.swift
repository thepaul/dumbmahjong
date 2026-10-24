/// The 42 distinct tile faces. Raw values are stable IDs used by tilesets and
/// save files, so never rename a case without migrating those.
public enum Face: String, CaseIterable, Codable, Sendable {
    case dots1, dots2, dots3, dots4, dots5, dots6, dots7, dots8, dots9
    case bamboo1, bamboo2, bamboo3, bamboo4, bamboo5, bamboo6, bamboo7, bamboo8, bamboo9
    case characters1, characters2, characters3, characters4, characters5
    case characters6, characters7, characters8, characters9
    case windEast, windSouth, windWest, windNorth
    case dragonRed, dragonGreen, dragonWhite
    case flowerPlum, flowerOrchid, flowerChrysanthemum, flowerBamboo
    case seasonSpring, seasonSummer, seasonAutumn, seasonWinter

    public enum Bonus: Sendable {
        case flower, season
    }

    /// Flowers and Seasons are bonus tiles: each is unique, and any two from the
    /// same group match.
    public var bonus: Bonus? {
        switch self {
        case .flowerPlum, .flowerOrchid, .flowerChrysanthemum, .flowerBamboo: .flower
        case .seasonSpring, .seasonSummer, .seasonAutumn, .seasonWinter: .season
        default: nil
        }
    }

    public func matches(_ other: Face) -> Bool {
        if let bonus {
            return bonus == other.bonus
        }
        return self == other
    }

    /// The standard 144-tile set: four of each suit and honor tile, plus one of
    /// each Flower and Season.
    public static let standardSet: [Face] = allCases.flatMap { face in
        Array(repeating: face, count: face.bonus == nil ? 4 : 1)
    }
}
