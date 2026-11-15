import AppKit

enum PlacementShape: String, Codable, CaseIterable {
    case square, circle, triangle

    var title: String {
        switch self { case .square: return "四角"; case .circle: return "丸"; case .triangle: return "三角形" }
    }

    func path(in rect: CGRect) -> NSBezierPath {
        switch self {
        case .square: return NSBezierPath(rect: rect)
        case .circle: return NSBezierPath(ovalIn: rect)
        case .triangle:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            return path
        }
    }
}

struct PlacementStyle: Codable {
    let shape: PlacementShape?
    let name: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let shortcut: String?
    let outlineRGB: [CGFloat]?

    init(name: String, color: NSColor, shortcut: String? = nil, outlineColor: NSColor? = nil, shape: PlacementShape? = nil) {
        self.shape = shape
        self.name = name
        self.shortcut = shortcut
        let outline = outlineColor?.usingColorSpace(.sRGB)
        outlineRGB = outline.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] }
        let rgb = color.usingColorSpace(.sRGB) ?? .black
        red = rgb.redComponent
        green = rgb.greenComponent
        blue = rgb.blueComponent
    }

    var outlineColor: NSColor? {
        guard let rgb = outlineRGB, rgb.count == 3 else { return nil }
        return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
    }

    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

struct MapCamera: Codable {
    let zoom: CGFloat
    let origin: CGPoint
}

final class Canvas: NSView {
    var document: MapDocument? { didSet { refreshView() } }
    var placementStyles: [String: PlacementStyle] = [:] { didSet { refreshView() } }
    var onPlacementShortcut: ((String) -> Bool)?
    var onOverviewChange: (() -> Void)?
    var selectedKind: String? { didSet { needsDisplay = true } }
    var platformTemplate = MovingPlatform(id: "preview", x: 0, y: 0)
    var selectedPlatformID: String? { didSet { refreshView() } }
    var onPlatformSelection: (() -> Void)?
    private var platformDragID: String?
    private var platformDragAnchor: GridPoint?
    var tile: [Int]?
    var marker: String? { didSet { needsDisplay = true } }
    var onCommit: ((MapDocument) -> Void)?
    var onHover: ((String) -> Void)?

    private var zoom: CGFloat = 0.3
    private var origin = CGPoint(x: 16, y: 16)
    private var start: MapDocument?
    private var previous: GridPoint?
    private var brush: Set<GridPoint> = []
    private var panning = false
    private var space = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var step: CGFloat { CGFloat(document?.tileSize ?? 32) * zoom }

    private static let colors: [String: NSColor] = [
        MapDocument.breakableKind: .systemOrange, "TerrainTiles": .systemBrown, "OneWayPlatforms": .systemTeal,
        MovingPlatform.kind: .systemMint, "GumPassBarriers": .systemCyan, "GumAnchors": .systemGreen,
        "Spikes": .systemRed, "GumBoxes": .systemMint, "Foods": .systemOrange, "Baguettes": .systemYellow, "MusicNotes": .systemPurple
    ]

    private static func routeMarkerColor(for path: String) -> NSColor? {
        switch path {
        case "PlacementMarkers/PlayerSpawn": return .systemGreen
        case "PlacementMarkers/Exit": return .systemPink
        default: return path == MapDocument.checkpointKind || path.hasPrefix(MapDocument.checkpointPrefix) ? .systemOrange : nil
        }
    }

    func placementStyle(for kind: String) -> PlacementStyle? {
        placementStyles[kind.hasPrefix(MapDocument.checkpointPrefix) ? MapDocument.checkpointKind : kind]
    }

    func placementColor(for kind: String) -> NSColor {
        placementStyle(for: kind)?.color ?? Self.colors[kind] ?? Self.routeMarkerColor(for: kind) ?? .systemBlue
    }

    func placementColor(for kind: String, tile: [Int]?) -> NSColor {
        placementColor(for: MapDocument.placementCategory(kind: kind, tile: tile))
    }

    func placementPath(in rect: CGRect, kind: String, tile: [Int]? = nil) -> NSBezierPath {
        let category = MapDocument.placementCategory(kind: kind, tile: tile)
        return (placementStyle(for: category)?.shape ?? .square).path(in: rect)
    }

    func drawPlacementOutline(in rect: CGRect, kind: String, tile: [Int]? = nil) {
        let category = MapDocument.placementCategory(kind: kind, tile: tile)
        guard let color = placementStyle(for: category)?.outlineColor else { return }
        let width = min(2, min(rect.width, rect.height) / 3)
        guard width > 0 else { return }
        color.setStroke()
        let inset = rect.insetBy(dx: width / 2, dy: width / 2)
        let path = placementPath(in: inset, kind: kind, tile: tile)
        path.lineWidth = width
        path.stroke()
    }

    static func placementRect(in cell: CGRect, kind: String) -> CGRect {
        if kind == "OneWayPlatforms" {
            return CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: cell.height / 5)
        }
        guard kind == "GumAnchors" || MapDocument.namedItemKinds.contains(kind) else { return cell }
        return cell.insetBy(dx: cell.width * 0.1, dy: cell.height * 0.1)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    var camera: MapCamera { MapCamera(zoom: zoom, origin: origin) }

    func restoreCamera(_ camera: MapCamera?) {
        guard let camera, camera.zoom.isFinite, camera.zoom > 0,
              camera.origin.x.isFinite, camera.origin.y.isFinite else {
            fit()
            return
        }
        zoom = camera.zoom
        origin = camera.origin
        refreshView()
    }

    var visibleMapRect: CGRect {
        CGRect(x: (bounds.minX - origin.x) / zoom, y: (bounds.minY - origin.y) / zoom,
               width: bounds.width / zoom, height: bounds.height / zoom)
    }

    func centerMap(on point: CGPoint) {
        origin = CGPoint(x: bounds.midX - point.x * zoom, y: bounds.midY - point.y * zoom)
        refreshView()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onOverviewChange?()
    }

    private func refreshView() {
        needsDisplay = true
        onOverviewChange?()
    }

    func fit() {
        guard let document, bounds.width > 32, bounds.height > 32 else { return }
        zoom = min((bounds.width - 32) / CGFloat(document.width * document.tileSize),
                   (bounds.height - 32) / CGFloat(document.height * document.tileSize))
        origin = CGPoint(x: 16, y: 16)
        refreshView()
    }

    private func rect(_ point: GridPoint) -> CGRect {
        CGRect(x: origin.x + CGFloat(point.x) * step, y: origin.y + CGFloat(point.y) * step,
               width: step, height: step)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard let document else {
            ("Godot で配置をコピーして ⌘V" as NSString).draw(at: CGPoint(x: 20, y: 20),
                withAttributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 16)])
            return
        }

        let map = CGRect(origin: origin, size: CGSize(width: CGFloat(document.width) * step,
                                                       height: CGFloat(document.height) * step))
        NSColor.controlBackgroundColor.setFill()
        map.fill()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for x in 0...document.width {
            let left = origin.x + CGFloat(x) * step
            grid.move(to: CGPoint(x: left, y: map.minY))
            grid.line(to: CGPoint(x: left, y: map.maxY))
        }
        for y in 0...document.height {
            let top = origin.y + CGFloat(y) * step
            grid.move(to: CGPoint(x: map.minX, y: top))
            grid.line(to: CGPoint(x: map.maxX, y: top))
        }
        NSColor.separatorColor.setStroke()
        grid.stroke()
        let occupied = Dictionary(grouping: document.cells, by: \.point)
        for (point, placements) in occupied {
            let cell = rect(point)
            guard dirtyRect.intersects(cell) else { continue }
            guard let visible = placements.first(where: { $0.kind == selectedKind }) ?? placements.last else {
                continue
            }
            placementColor(for: visible.kind, tile: visible.tile).setFill()
            let placement = Self.placementRect(in: cell, kind: visible.kind)
            placementPath(in: placement, kind: visible.kind, tile: visible.tile).fill()
            drawPlacementOutline(in: placement, kind: visible.kind, tile: visible.tile)
            if step >= 24 && placement.height >= 14 && visible.kind == selectedKind {
                let id = visible.tile
                let label = MapDocument.namedItemKinds.contains(visible.kind) ? "\(id[3])" : "\(id[1]),\(id[2])"
                (label as NSString).draw(at: CGPoint(x: cell.minX + 2, y: cell.minY + 2),
                    withAttributes: [.foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.65),
                                     .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)])
            }
        }
        for platform in platformsInDrawingOrder {
            drawPlatform(platform, origin: origin, scale: zoom,
                         selected: platform.id == selectedPlatformID, preview: false)
        }
        for path in document.markers.keys.sorted() {
            guard let position = document.markers[path] else { continue }
            let x = origin.x + position[0] * zoom
            let y = origin.y + position[1] * zoom
            let selected = path == marker || (selectedKind == MapDocument.checkpointKind
                && path.hasPrefix(MapDocument.checkpointPrefix))
            let label = placementStyle(for: path)?.name ?? String(path.split(separator: "/").last ?? "")
            let radius: CGFloat = Self.routeMarkerColor(for: path) == nil ? 4 : 7
            let dot = NSBezierPath(ovalIn: CGRect(x: x - radius, y: y - radius,
                                                 width: radius * 2, height: radius * 2))
            placementColor(for: path).setFill()
            placementPath(in: dot.bounds, kind: path).fill()
            drawPlacementOutline(in: dot.bounds, kind: path)
            if selected {
                NSColor.systemYellow.setStroke()
                dot.stroke()
            }
            if path == marker || step >= 16 {
                (label as NSString).draw(at: CGPoint(x: x + radius + 2, y: y - 7),
                    withAttributes: [.foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.controlBackgroundColor,
                                     .font: NSFont.systemFont(ofSize: 10)])
            }
        }
        if let hover, document.contains(hover) {
            if selectedKind == MovingPlatform.kind {
                var platform = platformTemplate
                platform.x = hover.x
                platform.y = hover.y
                guard document.overlappingPlatform(with: platform) == nil else { return }
                drawPlatform(platform, origin: origin, scale: zoom, selected: true, preview: true)
                return
            }
            let cell = rect(hover)
            let previewRect = selectedKind.map { Self.placementRect(in: cell, kind: $0) }
                ?? cell
            let preview = placementPath(in: previewRect, kind: selectedKind ?? "", tile: tile)
            if let selectedKind, tile != nil || selectedKind == MapDocument.checkpointKind {
                placementColor(for: selectedKind, tile: tile).withAlphaComponent(0.35).setFill()
                preview.fill()
                drawPlacementOutline(in: preview.bounds, kind: selectedKind, tile: tile)
            }
            NSColor.labelColor.setStroke()
            preview.stroke()
        }
    }

    private var hover: GridPoint?
    private func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func cell(at point: CGPoint) -> GridPoint? {
        guard let document else { return nil }
        let point = GridPoint(x: Int(floor((point.x - origin.x) / step)),
                              y: Int(floor((point.y - origin.y) / step)))
        return document.contains(point) ? point : nil
    }

    override func mouseMoved(with event: NSEvent) {
        hover = cell(at: location(event))
        onHover?(hover.map { "セル \($0.x), \($0.y)" } ?? "")
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        onHover?("")
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            space = true
            return
        }
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        if event.modifierFlags.intersection(modifiers).isEmpty,
           let key = event.charactersIgnoringModifiers?.lowercased(), onPlacementShortcut?(key) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { space = false } else { super.keyUp(with: event) }
    }

    override func resignFirstResponder() -> Bool {
        space = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        panning = space
        if !panning { begin(event, erase: false) }
    }

    override func rightMouseDown(with event: NSEvent) { begin(event, erase: true) }
    override func mouseDragged(with event: NSEvent) {
        if panning { pan(event.deltaX, event.deltaY) } else { stroke(event, erase: false) }
    }
    override func rightMouseDragged(with event: NSEvent) { stroke(event, erase: true) }
    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == 2 { pan(event.deltaX, event.deltaY) }
    }
    override func mouseUp(with event: NSEvent) { finish() }
    override func rightMouseUp(with event: NSEvent) { finish() }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            pan(event.scrollingDeltaX, event.scrollingDeltaY)
        } else {
            scale(by: exp(event.scrollingDeltaY * 0.045), at: location(event))
        }
    }

    override func magnify(with event: NSEvent) { scale(by: 1 + event.magnification, at: location(event)) }

    private func pan(_ x: CGFloat, _ y: CGFloat) {
        origin.x += x
        origin.y += y
        refreshView()
    }

    private func scale(by factor: CGFloat, at point: CGPoint) {
        let next = max(0.07, min(5, zoom * factor))
        origin = CGPoint(x: point.x - (point.x - origin.x) * next / zoom,
                         y: point.y - (point.y - origin.y) * next / zoom)
        zoom = next
        refreshView()
    }

    private func begin(_ event: NSEvent, erase: Bool) {
        start = document
        previous = nil
        brush.removeAll()
        if selectedKind == MovingPlatform.kind {
            beginPlatform(event, erase: erase)
        } else {
            stroke(event, erase: erase)
        }
    }

    private func stroke(_ event: NSEvent, erase: Bool) {
        guard let start, let point = cell(at: location(event)) else {
            previous = nil
            return
        }
        if selectedKind == MovingPlatform.kind {
            guard !erase, let id = platformDragID, let anchor = platformDragAnchor,
                  let index = start.movingPlatforms.firstIndex(where: { $0.id == id }) else { return }
            var next = start
            next.movingPlatforms[index].x += point.x - anchor.x
            next.movingPlatforms[index].y += point.y - anchor.y
            guard (try? next.validate()) != nil else { return }
            next.source = document?.source
            document = next
            onPlatformSelection?()
            return
        }
        var next = start
        next.source = document?.source
        if let marker, !erase, let position = start.markers[marker] {
            let size = Double(start.tileSize)
            next.markers[marker] = [
                Double(point.x) * size + position[0].truncatingRemainder(dividingBy: size),
                Double(point.y) * size + position[1].truncatingRemainder(dividingBy: size)
            ]
        } else if let selectedKind, erase || tile != nil || selectedKind == MapDocument.checkpointKind {
            let first = previous ?? point
            let dx = point.x - first.x
            let dy = point.y - first.y
            let length = max(1, abs(dx), abs(dy))
            for index in 0...length {
                let fraction = Double(index) / Double(length)
                brush.insert(GridPoint(x: first.x + Int((Double(dx) * fraction).rounded()),
                                       y: first.y + Int((Double(dy) * fraction).rounded())))
            }
            if selectedKind == MapDocument.checkpointKind {
                next.paintCheckpoints(in: brush, erase: erase)
            } else {
                next.cells.removeAll { $0.kind == selectedKind && brush.contains($0.point) }
                if !erase, let tile {
                    next.cells += brush.map { Placement(kind: selectedKind, x: $0.x, y: $0.y, tile: tile) }
                }
            }
        }
        previous = point
        next.cells.sort(by: Placement.ordered)
        document = next
    }

    var platformsInDrawingOrder: [MovingPlatform] {
        let platforms = document?.movingPlatforms ?? []
        return platforms.filter { $0.id != selectedPlatformID } + platforms.filter { $0.id == selectedPlatformID }
    }

    var selectedPlatform: MovingPlatform? {
        document?.movingPlatforms.first { $0.id == selectedPlatformID }
    }

    func updatePlatform(_ value: MovingPlatform) throws {
        guard var next = document else { return }
        if let id = selectedPlatformID, let index = next.movingPlatforms.firstIndex(where: { $0.id == id }) {
            var changed = value
            changed.id = id
            changed.x = next.movingPlatforms[index].x
            changed.y = next.movingPlatforms[index].y
            next.movingPlatforms[index] = changed
            try next.validate()
            let previous = document!
            guard next.movingPlatforms != previous.movingPlatforms else { return }
            document = next
            onCommit?(previous)
        } else {
            platformTemplate = value
            needsDisplay = true
        }
        onPlatformSelection?()
    }

    private func beginPlatform(_ event: NSEvent, erase: Bool) {
        guard let point = cell(at: location(event)) else { return }
        beginPlatform(at: point, erase: erase)
    }

    func beginPlatform(at point: GridPoint, erase: Bool) {
        guard var next = document else { return }
        if let index = next.movingPlatforms.lastIndex(where: { $0.contains(point) }) {
            selectedPlatformID = erase ? nil : next.movingPlatforms[index].id
            if erase {
                next.movingPlatforms.remove(at: index)
                document = next
            } else {
                platformDragID = selectedPlatformID
                platformDragAnchor = point
            }
        } else if !erase {
            var platform = platformTemplate
            platform.id = "p_" + UUID().uuidString.lowercased()
            platform.x = point.x
            platform.y = point.y
            if let existing = next.overlappingPlatform(with: platform) {
                selectedPlatformID = existing.id
                onPlatformSelection?()
                return
            }
            next.movingPlatforms.append(platform)
            do {
                try next.validate()
                document = next
                selectedPlatformID = platform.id
            } catch {
                onHover?(error.localizedDescription)
            }
        }
        onPlatformSelection?()
    }

    func drawPlatform(_ platform: MovingPlatform, origin: CGPoint, scale: CGFloat,
                      selected: Bool, preview: Bool, miniature: Bool = false) {
        let unit = CGFloat(document?.tileSize ?? 32) * scale
        let a = CGRect(x: origin.x + CGFloat(platform.x) * unit,
                       y: origin.y + CGFloat(platform.y) * unit,
                       width: CGFloat(platform.width_cells) * unit, height: max(1, 10 * scale))
        let b = a.offsetBy(dx: CGFloat(platform.offset.x) * unit, dy: CGFloat(platform.offset.y) * unit)
        let valid = document.map { (try? platform.validate(width: $0.width, height: $0.height)) != nil } ?? false
        let color = valid ? placementColor(for: MovingPlatform.kind) : NSColor.systemRed
        color.withAlphaComponent(preview ? 0.4 : 0.9).setFill()
        placementPath(in: a, kind: MovingPlatform.kind).fill()
        drawPlacementOutline(in: a, kind: MovingPlatform.kind)
        color.withAlphaComponent(selected ? 0.12 : 0.05).setFill()
        a.union(b).fill()
        color.withAlphaComponent(selected ? 0.9 : 0.4).setStroke()
        let outline = placementPath(in: b, kind: MovingPlatform.kind)
        outline.lineWidth = 1
        outline.stroke()
        let path = NSBezierPath()
        let from = CGPoint(x: a.midX, y: a.midY)
        let to = CGPoint(x: b.midX, y: b.midY)
        path.move(to: from)
        path.line(to: to)
        if !miniature {
            let length = hypot(to.x - from.x, to.y - from.y)
            if length > 0 {
                let dx = (to.x - from.x) / length
                let dy = (to.y - from.y) / length
                for (tip, sign, size) in [(to, CGFloat(1), CGFloat(7)), (from, CGFloat(-1), CGFloat(5))] {
                    path.move(to: CGPoint(x: tip.x - sign * dx * size - dy * size * 0.5,
                                         y: tip.y - sign * dy * size + dx * size * 0.5))
                    path.line(to: tip)
                    path.line(to: CGPoint(x: tip.x - sign * dx * size + dy * size * 0.5,
                                         y: tip.y - sign * dy * size - dx * size * 0.5))
                }
            }
        }
        path.lineWidth = selected ? 2 : 1
        path.stroke()
        if selected && !preview {
            let border = NSBezierPath(rect: a.insetBy(dx: -2, dy: -2))
            NSColor.systemYellow.setStroke()
            border.lineWidth = miniature ? 1 : 2
            border.stroke()
        }
        if selected && !miniature {
            let names = ["up": "上", "down": "下", "left": "左", "right": "右"]
            let label = "\(names[platform.direction] ?? "") \(platform.travel_cells)マス / \(platform.travel_cells * 32)px"
            (label as NSString).draw(at: CGPoint(x: (from.x + to.x) / 2 + 4, y: (from.y + to.y) / 2 - 16),
                withAttributes: [.foregroundColor: color, .backgroundColor: NSColor.controlBackgroundColor,
                                 .font: NSFont.systemFont(ofSize: 11)])
        }
    }

    private func finish() {
        defer { panning = false; start = nil; platformDragID = nil; platformDragAnchor = nil }
        guard let start, let document, start.cells != document.cells || start.markers != document.markers || start.movingPlatforms != document.movingPlatforms else { return }
        onCommit?(start)
    }
}

final class Minimap: NSView {
    weak var canvas: Canvas?
    private var isNavigating = false
    override var isFlipped: Bool { true }

    private func mapFrame(for map: MapDocument) -> CGRect {
        let available = bounds.insetBy(dx: 8, dy: 8)
        guard available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / CGFloat(map.width), available.height / CGFloat(map.height))
        let size = CGSize(width: CGFloat(map.width) * scale, height: CGFloat(map.height) * scale)
        return CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds).addClip()
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        guard let canvas, let map = canvas.document else { return }
        let frame = mapFrame(for: map)
        guard !frame.isEmpty else { return }
        let step = frame.width / CGFloat(map.width)
        let scale = step / CGFloat(map.tileSize)
        NSColor.windowBackgroundColor.setFill()
        frame.fill()

        for cell in map.cells {
            canvas.placementColor(for: cell.kind, tile: cell.tile).setFill()
            let bounds = CGRect(x: frame.minX + CGFloat(cell.x) * step, y: frame.minY + CGFloat(cell.y) * step,
                                width: step, height: step)
            let placement = Canvas.placementRect(in: bounds, kind: cell.kind)
            canvas.placementPath(in: placement, kind: cell.kind, tile: cell.tile).fill()
            canvas.drawPlacementOutline(in: placement, kind: cell.kind, tile: cell.tile)
        }
        for platform in canvas.platformsInDrawingOrder {
            canvas.drawPlatform(platform, origin: frame.origin, scale: scale,
                                selected: platform.id == canvas.selectedPlatformID, preview: false, miniature: true)
        }
        for (path, point) in map.markers {
            canvas.placementColor(for: path).setFill()
            let x = frame.minX + point[0] * scale
            let y = frame.minY + point[1] * scale
            let markerRect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
            canvas.placementPath(in: markerRect, kind: path).fill()
            canvas.drawPlacementOutline(in: markerRect, kind: path)
        }

        let visible = canvas.visibleMapRect
        let overview = CGRect(x: frame.minX + visible.minX * scale, y: frame.minY + visible.minY * scale,
                              width: visible.width * scale, height: visible.height * scale)
        let clipped = overview.intersection(frame)
        guard !clipped.isEmpty else { return }
        let outline = NSBezierPath(rect: clipped)
        NSColor.black.setStroke()
        outline.lineWidth = 3
        outline.stroke()
        NSColor.white.setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let canvas, let map = canvas.document, mapFrame(for: map).contains(point) else { return }
        isNavigating = true
        navigate(to: point)
        window?.makeFirstResponder(canvas)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isNavigating else { return }
        navigate(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        isNavigating = false
    }

    private func navigate(to point: CGPoint) {
        guard let canvas, let map = canvas.document else { return }
        let frame = mapFrame(for: map)
        guard !frame.isEmpty else { return }
        let scale = CGFloat(map.width * map.tileSize) / frame.width
        let x = min(max(point.x, frame.minX), frame.maxX)
        let y = min(max(point.y, frame.minY), frame.maxY)
        canvas.centerMap(on: CGPoint(x: (x - frame.minX) * scale, y: (y - frame.minY) * scale))
    }
}
