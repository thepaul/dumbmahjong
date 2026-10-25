import MahjongCore

extension Face {
    /// How VoiceOver reads the tile: "3 Bamboo", "Red Dragon", "Plum Flower".
    var spokenName: String {
        switch self {
        case .dots1, .dots2, .dots3, .dots4, .dots5, .dots6, .dots7, .dots8, .dots9:
            "\(rawValue.dropFirst(4)) Dots"
        case .bamboo1, .bamboo2, .bamboo3, .bamboo4, .bamboo5, .bamboo6, .bamboo7, .bamboo8, .bamboo9:
            "\(rawValue.dropFirst(6)) Bamboo"
        case .characters1, .characters2, .characters3, .characters4, .characters5,
             .characters6, .characters7, .characters8, .characters9:
            "\(rawValue.dropFirst(10)) Characters"
        case .windEast: "East Wind"
        case .windSouth: "South Wind"
        case .windWest: "West Wind"
        case .windNorth: "North Wind"
        case .dragonRed: "Red Dragon"
        case .dragonGreen: "Green Dragon"
        case .dragonWhite: "White Dragon"
        case .flowerPlum: "Plum Flower"
        case .flowerOrchid: "Orchid Flower"
        case .flowerChrysanthemum: "Chrysanthemum Flower"
        case .flowerBamboo: "Bamboo Flower"
        case .seasonSpring: "Spring Season"
        case .seasonSummer: "Summer Season"
        case .seasonAutumn: "Autumn Season"
        case .seasonWinter: "Winter Season"
        }
    }
}
