import Foundation

struct GridPoint: Hashable {
    let x: Int
    let y: Int
}

struct Placement: Codable, Equatable {
    let kind: String
    let x: Int
    let y: Int
    let tile: [Int]

    var point: GridPoint { GridPoint(x: x, y: y) }

    static func ordered(_ lhs: Placement, _ rhs: Placement) -> Bool {
        (lhs.kind, lhs.y, lhs.x) < (rhs.kind, rhs.y, rhs.x)
    }
}

struct Palette: Codable {
    let tileset: String
    let palette: [[Int]]
    let labels: [String]?
}

struct MovingPlatform: Codable, Equatable {
    var id: String
    var x: Int
    var y: Int
    var direction: String = "right"
    var travel_cells: Int = 4
    var width_cells: Int = 3
    var speed: Double = 64
    var endpoint_wait: Double = 0

    static let kind = "MovingPlatforms"
    static let directions = ["up", "down", "left", "right"]
    var offset: GridPoint {
        switch direction {
        case "up": return GridPoint(x: 0, y: -travel_cells)
        case "down": return GridPoint(x: 0, y: travel_cells)
        case "left": return GridPoint(x: -travel_cells, y: 0)
        default: return GridPoint(x: travel_cells, y: 0)
        }
    }
    func contains(_ point: GridPoint) -> Bool {
        point.y == y && (x..<(x + width_cells)).contains(point.x)
    }
    func overlaps(_ other: MovingPlatform) -> Bool {
        y == other.y && x < other.x + other.width_cells && other.x < x + width_cells
    }

    func validate(width: Int, height: Int) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !id.isEmpty, id.utf8.count <= 64, id.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }),
              Self.directions.contains(direction), (0..<width).contains(x), (0..<height).contains(y),
              (1...width).contains(travel_cells),
              (1...width).contains(width_cells), speed.isFinite, (32...160).contains(speed),
              endpoint_wait.isFinite, (0...5).contains(endpoint_wait) else {
            throw MapError("移動床の設定が不正です。")
        }
        for point in [GridPoint(x: x, y: y), GridPoint(x: x + offset.x, y: y + offset.y)] {
            guard point.x >= 0, point.x <= width - width_cells, (0..<height).contains(point.y) else {
                throw MapError("移動床の始点または終点がマップ範囲外です。")
            }
        }
    }
}

struct SourcePlacements: Codable {
    let cells: [Placement]
    let markers: [String: [Double]]
    let movingPlatforms: [MovingPlatform]
}

struct MapDocument: Codable {
    let version: Int
    let stage: String
    let width: Int
    let height: Int
    let tileSize: Int
    let base: String
    let layers: [String: Palette]
    var cells: [Placement]
    var markers: [String: [Double]]
    var movingPlatforms: [MovingPlatform]
    var source: SourcePlacements?

    static let order = ["TerrainTiles", "OneWayPlatforms", "GumPassBarriers",
                        "GumAnchors", "Spikes", "GumBoxes", "Foods", "Baguettes", "MusicNotes"]

    static let breakableKind = "BreakableBlocks"
    static let breakableTile = [4, 0, 0, 0]

    var placementCategories: [String] {
        var result = Self.order.filter { layers[$0] != nil }
        if layers["TerrainTiles"]?.palette.contains(Self.breakableTile) == true {
            result.insert(Self.breakableKind, at: 1)
        }
        result.append(MovingPlatform.kind)
        return result
    }

    static func placementCategory(kind: String, tile: [Int]?) -> String {
        kind == "TerrainTiles" && tile == breakableTile ? breakableKind : kind
    }

    static func layerKind(for category: String) -> String {
        category == breakableKind ? "TerrainTiles" : category
    }

    func placementTiles(for category: String) -> [[Int]] {
        if category == Self.breakableKind {
            return layers["TerrainTiles"]?.palette.filter { $0 == Self.breakableTile } ?? []
        }
        let tiles = layers[category]?.palette ?? []
        return category == "TerrainTiles" ? tiles.filter { $0 != Self.breakableTile } : tiles
    }

    static let namedItemKinds: Set<String> = ["Foods", "Baguettes", "MusicNotes"]

    static let checkpointKind = "Checkpoints"
    static let checkpointPrefix = checkpointKind + "/"

    mutating func paintCheckpoints(in points: Set<GridPoint>, erase: Bool) {
        let size = Double(tileSize)
        var occupied: Set<GridPoint> = []
        for (path, position) in markers where path.hasPrefix(Self.checkpointPrefix) {
            let point = GridPoint(x: min(width - 1, Int(position[0] / size)),
                                  y: max(0, Int(ceil(position[1] / size)) - 1))
            if erase && points.contains(point) {
                markers.removeValue(forKey: path)
            } else {
                occupied.insert(point)
            }
        }
        guard !erase else { return }
        var number = 1
        for point in points.subtracting(occupied).sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            while markers[Self.checkpointPrefix + "CheckpointMapEdit_\(number)"] != nil {
                number += 1
            }
            markers[Self.checkpointPrefix + "CheckpointMapEdit_\(number)"] = [
                (Double(point.x) + 0.5) * size, Double(point.y + 1) * size
            ]
            number += 1
        }
    }

    func contains(_ point: GridPoint) -> Bool {
        (0..<width).contains(point.x) && (0..<height).contains(point.y)
    }

    func overlappingPlatform(with candidate: MovingPlatform, excludingID: String? = nil) -> MovingPlatform? {
        movingPlatforms.lazy.filter { $0.id != excludingID && $0.overlaps(candidate) }.min {
            (abs($0.x - candidate.x), $0.x, $0.id) < (abs($1.x - candidate.x), $1.x, $1.id)
        }
    }

    func validate() throws {
        let widths = ["res://scenes/title.tscn": 40,
                      "res://scenes/stages/theater_stage.tscn": 160,
                      "res://scenes/stages/time_attack.tscn": 692]
        guard version == 2, widths[stage] == width, height == 24, tileSize == 32,
              base.count == 64, base.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              layers["TerrainTiles"] != nil,
              Set(layers.keys).isSubset(of: Set(Self.order)),
              markers["PlacementMarkers/PlayerSpawn"] != nil, markers["PlacementMarkers/Exit"] != nil else {
            throw MapError("ステージ情報や配置形式が未対応です。Godotからステージをコピーし直してください。")
        }
        for (name, layer) in layers {
            guard !layer.tileset.isEmpty, layer.palette.allSatisfy({ tile in
                tile.count == 4 && tile.allSatisfy { (0...Int(Int32.max)).contains($0) }
            }) else { throw MapError("タイルパレットが不正です: \(name)") }
        }
        var ids: Set<String> = []
        for platform in movingPlatforms {
            try platform.validate(width: width, height: height)
            guard ids.insert(platform.id).inserted else {
                throw MapError("移動床のIDが重複しています。")
            }
        }
        for platform in movingPlatforms {
            if overlappingPlatform(with: platform, excludingID: platform.id) != nil {
                throw MapError("移動床の配置範囲が重なっています（セル \(platform.x), \(platform.y)）。")
            }
        }
        var occupied: [String: Set<GridPoint>] = [:]
        for cell in cells {
            guard contains(cell.point), layers[cell.kind]?.palette.contains(cell.tile) == true,
                  occupied[cell.kind, default: []].insert(cell.point).inserted else {
                throw MapError("範囲外、重複、または未知のタイルがあります。")
            }
        }
        for (path, position) in markers {
            guard position.count == 2,
                  (0...Double(width * tileSize)).contains(position[0]),
                  (0...Double(height * tileSize)).contains(position[1]) else {
                throw MapError("マーカーの位置が不正です: \(path)")
            }
        }
    }
}

struct MapError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
