import AppKit

func rejects(_ action: () throws -> Void) {
    do { try action(); fatalError("Expected overlap rejection") } catch {}
}

let a = MovingPlatform(id: "a", x: 10, y: 8, width_cells: 3)
let b = MovingPlatform(id: "b", x: 20, y: 8, width_cells: 2)
var map = MapDocument(version: 2, stage: "res://scenes/stages/theater_stage.tscn", width: 160,
                      height: 24, tileSize: 32, base: String(repeating: "0", count: 64),
                      layers: ["TerrainTiles": Palette(tileset: "res://assets/tilesets/theater_tileset.tres", palette: [[0,8,3,0]], labels: nil)],
                      cells: [], markers: ["PlacementMarkers/PlayerSpawn": [160,640], "PlacementMarkers/Exit": [4944,384]],
                      movingPlatforms: [a,b], source: nil)
try map.validate()
var wideMap = MapDocument(version: map.version, stage: "res://scenes/stages/time_attack.tscn", width: 692,
                          height: map.height, tileSize: map.tileSize, base: map.base, layers: map.layers,
                          cells: map.cells, markers: map.markers, movingPlatforms: [], source: nil)
wideMap.movingPlatforms = [MovingPlatform(id: "edge", x: 691, y: 8, direction: "left", travel_cells: 1, width_cells: 1)]
try wideMap.validate()
wideMap.movingPlatforms[0].x = 692
rejects { try wideMap.validate() }
for candidate in [MovingPlatform(id: "partial", x: 8, y: 8, width_cells: 3),
                  MovingPlatform(id: "inside", x: 11, y: 8, width_cells: 1),
                  MovingPlatform(id: "cover", x: 8, y: 8, width_cells: 8)] {
    var changed = map
    changed.movingPlatforms.append(candidate)
    rejects { try changed.validate() }
    assert(map.overlappingPlatform(with: candidate)?.id == "a")
}
for candidate in [MovingPlatform(id: "adjacent", x: 13, y: 8), MovingPlatform(id: "other_row", x: 10, y: 9)] {
    var changed = map
    changed.movingPlatforms.append(candidate)
    try changed.validate()
}
var moving = map
moving.movingPlatforms[0].x = 19
rejects { try moving.validate() }
var widening = map
widening.movingPlatforms[0].width_cells = 12
rejects { try widening.validate() }

let canvas = Canvas(frame: CGRect(x: 0,y: 0,width: 600,height: 250))
canvas.document = map
canvas.selectedKind = MovingPlatform.kind
var selectionCount = 0
var redrawCount = 0
canvas.onPlatformSelection = { selectionCount += 1 }
canvas.onOverviewChange = { redrawCount += 1 }
canvas.beginPlatform(at: GridPoint(x: 8,y: 8), erase: false)
assert(canvas.document!.movingPlatforms == map.movingPlatforms)
assert(canvas.selectedPlatformID == "a" && selectionCount == 1 && redrawCount > 0)
assert(canvas.platformsInDrawingOrder.last?.id == "a")
canvas.beginPlatform(at: GridPoint(x: 11,y: 8), erase: false)
assert(canvas.document!.movingPlatforms.count == 2 && canvas.selectedPlatformID == "a")
canvas.beginPlatform(at: GridPoint(x: 30,y: 8), erase: false)
assert(canvas.document!.movingPlatforms.count == 3 && canvas.selectedPlatform?.x == 30)
canvas.beginPlatform(at: GridPoint(x: 13,y: 8), erase: false)
assert(canvas.document!.movingPlatforms.count == 4 && canvas.selectedPlatform?.x == 13)
canvas.selectedPlatformID = "a"
let before = canvas.document!.movingPlatforms
var changed = a
changed.width_cells = 12
rejects { try canvas.updatePlatform(changed) }
assert(canvas.document!.movingPlatforms == before && canvas.selectedPlatformID == "a")
canvas.beginPlatform(at: GridPoint(x: 11,y: 8), erase: true)
assert(!canvas.document!.movingPlatforms.contains { $0.id == "a" } && canvas.selectedPlatformID == nil)

// Render the real draw helper offscreen; no app windows or user sessions are opened.
func yellowPixels(selected: Bool, preview: Bool, miniature: Bool = false) -> Int {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 120,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = false
    NSColor.black.setFill()
    CGRect(x: 0,y: 0,width: 300,height: 120).fill()
    canvas.drawPlatform(a, origin: CGPoint(x: -60,y: -20), scale: 0.25,
                        selected: selected, preview: preview, miniature: miniature)
    NSGraphicsContext.restoreGraphicsState()
    var count = 0
    for y in 0..<120 {
        for x in 0..<300 {
            let c = bitmap.colorAt(x: x,y: y)!.usingColorSpace(.deviceRGB)!
            if c.redComponent > 0.7 && c.greenComponent > 0.5 && c.blueComponent < 0.4 { count += 1 }
        }
    }
    if selected && !preview && !miniature {
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/mapedit-platform-selection.png"))
    }
    return count
}
assert(yellowPixels(selected: true,preview: false) > 20)
assert(yellowPixels(selected: false,preview: false) == 0)
assert(yellowPixels(selected: true,preview: true) == 0)
assert(yellowPixels(selected: true,preview: false,miniature: true) > 10)
print("PASS: overlap/adjacency, select instead of duplicate, resize rejection, selection repaint and yellow canvas/minimap outline")

// Appearance settings survive persistence and share geometry across all renderers.
for shape in PlacementShape.allCases {
    let style = PlacementStyle(name: "shape", color: .red, shortcut: "q", outlineColor: .black, shape: shape)
    let restored = try JSONDecoder().decode(PlacementStyle.self, from: JSONEncoder().encode(style))
    assert(restored.shape == shape && restored.shortcut == "q" && restored.outlineColor != nil)
    let rect = CGRect(x: 10, y: 20, width: 30, height: 30)
    assert(shape.path(in: rect).bounds == rect)
    assert(shape.path(in: rect).contains(CGPoint(x: 25, y: 35)))
    if shape != .square { assert(!shape.path(in: rect).contains(CGPoint(x: 11, y: 21))) }
}
print("Placement shapes PASS")
