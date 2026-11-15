import AppKit
import CryptoKit
import Network

private struct SavedSession: Codable {
    let map: MapDocument
    let baseline: Data?
    let file: URL?
    let camera: MapCamera?
}

private final class PaletteGrid: NSGridView {
    override var isFlipped: Bool { true }
}

private struct PasteResponse: Decodable {
    let status: String
    let message: String
}

final class MapEdit: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
    private let canvas = Canvas()
    private let paletteScroll = NSScrollView()
    private let preferences = UserDefaults(suiteName: "BungeeGumMapEdit")
    private static let stylesKey = "mapedit.placementStyles"
    private let styleButton = NSButton(title: "タイル設定…", target: nil, action: nil)
    private let styleName = NSTextField(string: "")
    private let styleShortcut = NSTextField(string: "")
    private let styleColor = NSColorWell()
    private let styleOutlineEnabled = NSButton(checkboxWithTitle: "縁取りを有効にする", target: nil, action: nil)
    private let styleOutlineColor = NSColorWell()
    private let styleFeedback = NSTextField(labelWithString: "")
    private var styleKind: String?
    private lazy var stylePanel = makeStylePanel()
    private var categoryButtons: [NSButton] = []
    private let variantLabel = NSTextField(labelWithString: "タイル")
    private let variant = NSPopUpButton(frame: .zero, pullsDown: false)
    private let platformControls = NSStackView()
    private let platformHeading = NSTextField(labelWithString: "次に置く移動床")
    private let platformDirection = NSPopUpButton(frame: .zero, pullsDown: false)
    private let platformTravel = NSTextField(string: "4")
    private let platformWidth = NSTextField(string: "3")
    private let platformSpeed = NSTextField(string: "64")
    private let platformWait = NSTextField(string: "0")
    private let platformFeedback = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let history = UndoManager()
    private var baseline: Data?
    private var file: URL?
    private var categories: [String] = []
    private var variants: [[Int]] = []
    private var pasteConnection: NWConnection?
    private var pasteTrace = "-"
    private var sentMap: MapDocument?
    private var loadedMapID = UUID()
    private var sentMapID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        history.levelsOfUndo = 50
        history.groupsByEvent = false
        window.title = "MapEdit"
        window.delegate = self
        window.minSize = NSSize(width: 650, height: 350)
        window.center()
        installMenu()

        if let data = preferences?.data(forKey: Self.stylesKey),
           let styles = try? JSONDecoder().decode([String: PlacementStyle].self, from: data) {
            canvas.placementStyles = styles
        }
        styleButton.target = self
        styleButton.action = #selector(editPlacementStyle)
        variant.target = self
        variant.action = #selector(selectVariant)
        let sendButton = NSButton(title: "Godot に送る", target: self, action: #selector(sendMap))
        let fitButton = NSButton(title: "全体表示", target: self, action: #selector(fit))
        let categoryLabel = NSTextField(labelWithString: "配置種別")
        variant.bezelStyle = .rounded
        variant.isBordered = true
        paletteScroll.hasVerticalScroller = true
        paletteScroll.autohidesScrollers = true
        paletteScroll.drawsBackground = true
        paletteScroll.backgroundColor = .controlBackgroundColor
        setupPlatformControls()
        let tools = NSStackView(views: [categoryLabel, paletteScroll, styleButton, variantLabel, variant, platformControls, sendButton, fitButton, status])
        tools.orientation = .vertical
        tools.alignment = .leading
        tools.spacing = 8
        let sidebar = NSBox()
        sidebar.boxType = .custom
        sidebar.fillColor = .controlBackgroundColor
        sidebar.contentViewMargins = .zero
        sidebar.contentView?.addSubview(tools)
        tools.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "左ドラッグで配置・移動　右ドラッグで消去　Space + ドラッグでパン　ホイール／ピンチでズーム")
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        let root = NSView()
        root.wantsLayer = true
        window.contentView = root
        let minimap = Minimap()
        minimap.canvas = canvas
        minimap.toolTip = "ミニマップをクリックまたは左ドラッグして表示位置を移動"
        canvas.onOverviewChange = { [weak minimap] in minimap?.needsDisplay = true }
        for view in [canvas, sidebar, minimap, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 310),
            tools.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
            tools.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),
            tools.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            tools.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            paletteScroll.widthAnchor.constraint(equalTo: tools.widthAnchor),
            variant.widthAnchor.constraint(equalTo: tools.widthAnchor),
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            minimap.topAnchor.constraint(equalTo: canvas.bottomAnchor),
            minimap.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            minimap.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            minimap.heightAnchor.constraint(equalToConstant: 84),
            hint.topAnchor.constraint(equalTo: minimap.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -12),
            hint.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        canvas.onPlacementShortcut = { [weak self] key in
            guard let self, let index = self.categories.firstIndex(where: {
                self.canvas.placementStyle(for: $0)?.shortcut == key
            }) else { return false }
            self.selectCategory(at: index)
            self.categoryButtons[index].scrollToVisible(self.categoryButtons[index].bounds)
            return true
        }
        canvas.onPlatformSelection = { [weak self] in self?.refreshPlatformControls() }
        canvas.onHover = { [weak self] label in self?.status.stringValue = label }
        canvas.onCommit = { [weak self] previous in
            self?.remember(previous)
            self?.refreshTitle()
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
        refreshPalette()
        restoreSession()
    }

    private func installMenu() {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [(String, Selector, String, NSEvent.ModifierFlags)]) {
            let parent = NSMenuItem()
            let menu = NSMenu(title: title)
            parent.submenu = menu
            main.addItem(parent)
            for (title, action, key, flags) in items {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
                item.target = self
                item.keyEquivalentModifierMask = flags
                menu.addItem(item)
            }
        }
        submenu("MapEdit", [("MapEdit を終了", #selector(quit), "q", [.command])])
        submenu("ファイル", [
            ("開く…", #selector(openFile), "o", [.command]),
            ("保存", #selector(save), "s", [.command]),
            ("名前を付けて保存…", #selector(saveAs), "s", [.command, .shift])
        ])
        submenu("編集", [
            ("元に戻す", #selector(undo), "z", [.command]),
            ("やり直す", #selector(redo), "z", [.command, .shift]),
            ("配置を貼り付け", #selector(pasteMap), "v", [.command])
        ])
        submenu("表示", [("全体表示", #selector(fit), "0", [.command])])
        NSApp.mainMenu = main
    }

    private func refreshPalette() {
        categoryButtons.removeAll()
        guard let map = canvas.document else {
            paletteScroll.documentView = nil
            variant.isEnabled = false
            styleButton.isEnabled = false
            return
        }
        categories = map.placementCategories
            + [MapDocument.checkpointKind]
            + map.markers.keys.filter { !$0.hasPrefix(MapDocument.checkpointPrefix) }.sorted()
        for (index, kind) in categories.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(chooseCategory(_:)))
            button.tag = index
            updateCategoryLabel(button, kind: kind)
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .rounded
            button.lineBreakMode = .byTruncatingTail
            button.widthAnchor.constraint(equalToConstant: 132).isActive = true
            categoryButtons.append(button)
        }
        let palette = PaletteGrid()
        palette.columnSpacing = 6
        palette.rowSpacing = 4
        let columns = 2
        for start in stride(from: 0, to: categoryButtons.count, by: columns) {
            let end = min(start + columns, categoryButtons.count)
            palette.addRow(with: Array(categoryButtons[start..<end]))
        }
        palette.setFrameSize(palette.fittingSize)
        paletteScroll.documentView = palette
        palette.scroll(.zero)
        styleButton.isEnabled = true
        selectCategory(at: 0)
    }

    private func updateCategoryLabel(_ button: NSButton, kind: String) {
        let title = placementName(for: kind)
        let label = NSMutableAttributedString(string: "■  " + title)
        label.addAttribute(.foregroundColor, value: canvas.placementColor(for: kind),
                           range: NSRange(location: 0, length: 1))
        button.attributedTitle = label
        let shortcut = canvas.placementStyle(for: kind)?.shortcut
        button.toolTip = shortcut.map { "\(title) [\($0.uppercased())]" } ?? title
    }

    private func placementName(for kind: String) -> String {
        let labels = [MapDocument.breakableKind: "破壊可能ブロック", "TerrainTiles": "地形", "OneWayPlatforms": "一方通行床", "GumPassBarriers": "バリア", MovingPlatform.kind: "移動床",
                      "GumAnchors": "ガムアンカー", "Spikes": "即死トゲ", "GumBoxes": "可動ブロック", "Foods": "食べ物", "Baguettes": "スター", "MusicNotes": "音符", MapDocument.checkpointKind: "チェックポイント"]
        let name = String(kind.split(separator: "/").last ?? "")
        return canvas.placementStyle(for: kind)?.name ?? labels[kind]
            ?? (name == "PlayerSpawn" ? "スタート" : name == "Exit" ? "ゴール" : name)
    }

    @objc private func editPlacementStyle() {
        guard let index = categoryButtons.firstIndex(where: { $0.state == .on }),
              categories.indices.contains(index) else { return }
        let selected = categories[index]
        styleKind = selected
        let panel = stylePanel
        panel.title = "タイル設定 — " + placementName(for: selected)
        populateStyleFields(for: selected)
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeStylePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 245),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        styleName.delegate = self
        styleShortcut.delegate = self
        styleShortcut.placeholderString = "英数字1キー・空欄で解除"
        styleColor.target = self
        styleColor.action = #selector(changeStyleColor)
        styleColor.isContinuous = true
        styleOutlineEnabled.target = self
        styleOutlineEnabled.action = #selector(changeStyleOutline)
        styleOutlineColor.target = self
        styleOutlineColor.action = #selector(changeStyleOutline)
        styleOutlineColor.isContinuous = true
        let fields = NSGridView(views: [
            [NSTextField(labelWithString: "表示名"), styleName],
            [NSTextField(labelWithString: "色"), styleColor],
            [NSTextField(labelWithString: "ショートカット"), styleShortcut],
            [NSTextField(labelWithString: "縁取り"), styleOutlineEnabled],
            [NSTextField(labelWithString: "縁取りの色"), styleOutlineColor]
        ])
        styleFeedback.textColor = .secondaryLabelColor
        let reset = NSButton(title: "既定に戻す", target: self, action: #selector(resetPlacementStyle))
        let stack = NSStackView(views: [fields, styleFeedback, reset])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let content = NSView()
        panel.contentView = content
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            styleName.widthAnchor.constraint(equalToConstant: 220),
            styleShortcut.widthAnchor.constraint(equalToConstant: 220)
        ])
        return panel
    }

    private func populateStyleFields(for kind: String) {
        styleName.stringValue = placementName(for: kind)
        styleColor.color = canvas.placementColor(for: kind)
        styleShortcut.stringValue = canvas.placementStyle(for: kind)?.shortcut?.uppercased() ?? ""
        let outline = canvas.placementStyle(for: kind)?.outlineColor
        styleOutlineEnabled.state = outline == nil ? .off : .on
        styleOutlineColor.color = outline ?? .black
        styleOutlineColor.isEnabled = outline != nil
        styleFeedback.stringValue = "変更はすぐに保存されます"
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let kind = styleKind, let field = notification.object as? NSTextField else { return }
        let previous = canvas.placementStyle(for: kind)
        if field === styleName {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                styleFeedback.stringValue = "表示名を入力してください"
                return
            }
            savePlacementStyle(PlacementStyle(name: name, color: canvas.placementColor(for: kind),
                                              shortcut: previous?.shortcut, outlineColor: previous?.outlineColor), for: kind)
        } else if field === styleShortcut {
            let key = field.stringValue.lowercased()
            guard key.isEmpty || (key.utf8.count == 1 && "abcdefghijklmnopqrstuvwxyz0123456789".contains(key)) else {
                styleFeedback.stringValue = "英数字1キーを入力してください"
                return
            }
            guard key.isEmpty || !canvas.placementStyles.contains(where: { $0.key != kind && $0.value.shortcut == key }) else {
                styleFeedback.stringValue = "そのキーは別の配置種別に割り当て済みです"
                return
            }
            savePlacementStyle(PlacementStyle(name: placementName(for: kind), color: canvas.placementColor(for: kind),
                                              shortcut: key.isEmpty ? nil : key, outlineColor: previous?.outlineColor), for: kind)
        }
    }

    @objc private func changeStyleColor() {
        guard let kind = styleKind else { return }
        savePlacementStyle(PlacementStyle(name: placementName(for: kind), color: styleColor.color,
                                          shortcut: canvas.placementStyle(for: kind)?.shortcut,
                                          outlineColor: canvas.placementStyle(for: kind)?.outlineColor), for: kind)
    }

    @objc private func changeStyleOutline() {
        guard let kind = styleKind else { return }
        let enabled = styleOutlineEnabled.state == .on
        styleOutlineColor.isEnabled = enabled
        if !enabled { styleOutlineColor.deactivate() }
        savePlacementStyle(PlacementStyle(name: placementName(for: kind), color: canvas.placementColor(for: kind),
                                          shortcut: canvas.placementStyle(for: kind)?.shortcut,
                                          outlineColor: enabled ? styleOutlineColor.color : nil), for: kind)
    }

    @objc private func resetPlacementStyle() {
        guard let kind = styleKind else { return }
        savePlacementStyle(nil, for: kind)
        populateStyleFields(for: kind)
    }

    private func savePlacementStyle(_ style: PlacementStyle?, for kind: String) {
        var styles = canvas.placementStyles
        styles[kind] = style
        do {
            preferences?.set(try JSONEncoder().encode(styles), forKey: Self.stylesKey)
            canvas.placementStyles = styles
            if let index = categories.firstIndex(of: kind) {
                updateCategoryLabel(categoryButtons[index], kind: kind)
            }
            stylePanel.title = "タイル設定 — " + placementName(for: kind)
            styleFeedback.stringValue = "変更はすぐに保存されます"
        } catch {
            styleFeedback.stringValue = error.localizedDescription
        }
    }

    private func setupPlatformControls() {
        platformDirection.addItems(withTitles: ["上", "下", "左", "右"])
        platformControls.orientation = .vertical
        platformControls.alignment = .leading
        platformControls.spacing = 5
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "移動方向"), platformDirection],
            [NSTextField(labelWithString: "移動マス数"), platformTravel],
            [NSTextField(labelWithString: "床の横幅（マス）"), platformWidth],
            [NSTextField(labelWithString: "速度（px/s）"), platformSpeed],
            [NSTextField(labelWithString: "端の待機（秒）"), platformWait]
        ])
        for field in [platformTravel, platformWidth, platformSpeed, platformWait] {
            field.widthAnchor.constraint(equalToConstant: 90).isActive = true
            field.target = self
            field.action = #selector(applyPlatformSettings)
        }
        let apply = NSButton(title: "設定を確定", target: self, action: #selector(applyPlatformSettings))
        let deselect = NSButton(title: "新規配置へ", target: self, action: #selector(deselectPlatform))
        let buttons = NSStackView(views: [apply, deselect])
        for view in [platformHeading, grid, buttons, platformFeedback] { platformControls.addArrangedSubview(view) }
        platformFeedback.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        platformFeedback.textColor = .secondaryLabelColor
        platformControls.isHidden = true
    }

    private func refreshPlatformControls() {
        let selected = canvas.selectedPlatform
        let platform = selected ?? canvas.platformTemplate
        platformHeading.stringValue = selected == nil ? "次に置く移動床" : "選択中の移動床"
        platformDirection.selectItem(at: MovingPlatform.directions.firstIndex(of: platform.direction) ?? 3)
        platformTravel.stringValue = String(platform.travel_cells)
        platformWidth.stringValue = String(platform.width_cells)
        platformSpeed.stringValue = String(platform.speed)
        platformWait.stringValue = String(platform.endpoint_wait)
        platformFeedback.stringValue = selected == nil ? "左クリックで一台配置。既存床を選択して編集・ドラッグ移動。" : platformWarning(platform)
    }

    private func platformWarning(_ platform: MovingPlatform) -> String {
        guard let map = canvas.document else { return "" }
        let left = min(platform.x, platform.x + platform.offset.x)
        let top = min(platform.y, platform.y + platform.offset.y)
        let right = max(platform.x, platform.x + platform.offset.x) + platform.width_cells
        let bottom = max(platform.y, platform.y + platform.offset.y) + 1
        if map.cells.contains(where: {
            ["TerrainTiles", "GumPassBarriers"].contains($0.kind) && (left..<right).contains($0.x)
                && (max(0, top - 2)..<bottom).contains($0.y)
        }) { return "警告：移動範囲か頭上空間に地形・バリアがあります。" }
        for other in map.movingPlatforms where other.id != platform.id {
            let a = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            let b = CGRect(x: min(other.x, other.x + other.offset.x), y: min(other.y, other.y + other.offset.y),
                           width: other.width_cells + abs(other.offset.x), height: 1 + abs(other.offset.y))
            if a.intersects(b) { return "警告：他の移動床と移動範囲が重なります。" }
        }
        return "範囲矢印は往復区間。右クリックで一台削除。"
    }

    @objc private func deselectPlatform() {
        if let selected = canvas.selectedPlatform { canvas.platformTemplate = selected }
        canvas.selectedPlatformID = nil
        canvas.needsDisplay = true
        refreshPlatformControls()
        window.makeFirstResponder(canvas)
    }

    @objc private func applyPlatformSettings() {
        guard let travel = Int(platformTravel.stringValue), let width = Int(platformWidth.stringValue),
              let speed = Double(platformSpeed.stringValue), let wait = Double(platformWait.stringValue),
              MovingPlatform.directions.indices.contains(platformDirection.indexOfSelectedItem) else {
            platformFeedback.stringValue = "マス数は整数、速度・待機時間は数値で指定してください。"
            return
        }
        var value = canvas.selectedPlatform ?? canvas.platformTemplate
        value.direction = MovingPlatform.directions[platformDirection.indexOfSelectedItem]
        value.travel_cells = travel
        value.width_cells = width
        value.speed = speed
        value.endpoint_wait = wait
        do {
            if canvas.selectedPlatform == nil {
                guard (1...192).contains(travel), (1...192).contains(width), speed.isFinite,
                      (32...160).contains(speed), wait.isFinite, (0...5).contains(wait) else {
                    throw MapError("移動・横幅は1以上、速度32〜160、待機0〜5秒で指定してください。")
                }
            }
            try canvas.updatePlatform(value)
            window.makeFirstResponder(canvas)
        } catch { platformFeedback.stringValue = error.localizedDescription }
    }

    @objc private func chooseCategory(_ sender: NSButton) {
        selectCategory(at: sender.tag)
    }

    private func selectCategory(at index: Int) {
        guard categories.indices.contains(index), let map = canvas.document else { return }
        for button in categoryButtons { button.state = button.tag == index ? .on : .off }
        let selected = categories[index]
        variantLabel.stringValue = selected == "Foods" ? "料理の種類" : "タイル"
        variant.removeAllItems()
        variants = map.placementTiles(for: selected)
        let layerKind = MapDocument.layerKind(for: selected)
        canvas.selectedKind = map.layers[layerKind] != nil || selected == MapDocument.checkpointKind || selected == MovingPlatform.kind ? layerKind : nil
        canvas.selectedPlatformID = nil
        platformControls.isHidden = selected != MovingPlatform.kind
        variant.isHidden = selected == MovingPlatform.kind
        variantLabel.isHidden = selected == MovingPlatform.kind
        refreshPlatformControls()
        canvas.marker = map.markers[selected] == nil ? nil : selected
        let source = map.layers[layerKind]
        let labels = source?.labels ?? []
        variant.addItems(withTitles: variants.enumerated().map { index, id in
            let identifier = "\(id[0]) / \(id[1]),\(id[2]) / \(id[3])"
            if selected == MapDocument.breakableKind { return "茶色レンガ" }
            if selected == "OneWayPlatforms", id[0] == 1, id[2] == 0, (0...3).contains(id[1]) {
                return ["左端", "中間", "右端", "単独"][id[1]]
            }
            let labelIndex = source?.palette.firstIndex(of: id) ?? index
            guard labels.indices.contains(labelIndex), !labels[labelIndex].isEmpty else { return identifier }
            return MapDocument.namedItemKinds.contains(selected) ? labels[labelIndex] : "\(labels[labelIndex]) · \(identifier)"
        })
        variant.isEnabled = !variants.isEmpty
        selectVariant()
    }

    @objc private func selectVariant() {
        let index = variant.indexOfSelectedItem
        canvas.tile = variants.indices.contains(index) ? variants[index] : nil
        variant.toolTip = variant.titleOfSelectedItem
        window.makeFirstResponder(canvas)
    }

    @objc private func fit() { canvas.fit() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func undo() { history.undo() }
    @objc private func redo() { history.redo() }

    private func remember(_ previous: MapDocument) {
        history.beginUndoGrouping()
        history.registerUndo(withTarget: self) { editor in
            guard let current = editor.canvas.document else { return }
            editor.remember(current)
            var restored = previous
            restored.source = current.source
            editor.canvas.document = restored
            editor.refreshPlatformControls()
            editor.refreshTitle()
        }
        history.endUndoGrouping()
    }

    private func encode(_ map: MapDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var normalized = map
        normalized.cells.sort(by: Placement.ordered)
        normalized.movingPlatforms.sort { $0.id < $1.id }
        return try encoder.encode(normalized)
    }

    private var dirty: Bool {
        guard let map = canvas.document else { return false }
        return (try? encode(map)) != baseline
    }

    private func refreshTitle() {
        let name = file?.lastPathComponent ?? canvas.document?.stage.split(separator: "/").last.map(String.init)
        window.title = name.map { "MapEdit — \($0)" } ?? "MapEdit"
        window.isDocumentEdited = dirty
    }

    private func replace(with data: Data, file: URL?) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["version"] as? Int == 2 else {
            throw MapError("配置形式が古いか未対応です。Godotからステージをコピーし直してください。")
        }
        var map = try JSONDecoder().decode(MapDocument.self, from: data)
        map.cells.sort(by: Placement.ordered)
        try map.validate()
        let normalized = try encode(map)
        guard allowReplacement() else { return }
        load(map, file: file, baseline: normalized)
    }

    private func load(_ map: MapDocument, file: URL?, baseline: Data?, camera: MapCamera? = nil) {
        if styleKind != nil {
            styleColor.deactivate()
            styleOutlineColor.deactivate()
            stylePanel.orderOut(nil)
            styleKind = nil
        }
        loadedMapID = UUID()
        self.file = file
        self.baseline = baseline
        canvas.document = map
        history.removeAllActions()
        refreshPalette()
        refreshTitle()
        window.contentView?.layoutSubtreeIfNeeded()
        canvas.restoreCamera(camera)
        window.makeFirstResponder(canvas)
    }

    @objc private func sendMap() {
        guard let map = canvas.document else {
            logPaste("send skipped: no map")
            return
        }
        guard pasteConnection == nil else {
            logPaste("send skipped: request already in progress", trace: pasteTrace)
            return
        }
        do {
            try map.validate()
            var payload = try encode(map)
            payload.append(10)
            let trace = SHA256.hash(data: payload).prefix(6).map { String(format: "%02x", $0) }.joined()
            pasteTrace = trace
            logPaste("connect 127.0.0.1:47653 stage=\(map.stage) bytes=\(payload.count)", trace: trace)
            let connection = NWConnection(host: "127.0.0.1", port: 47653, using: .tcp)
            pasteConnection = connection
            sentMapID = loadedMapID
            status.stringValue = "Godot に送信中…"
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, self.pasteConnection === connection else { return }
                switch state {
                case .ready:
                    self.logPaste("connected", trace: trace)
                    connection.send(content: payload, completion: .contentProcessed { error in
                        guard self.pasteConnection === connection else { return }
                        if let error {
                            self.finishSend(connection, error: error)
                            return
                        }
                        self.sentMap = map
                        self.status.stringValue = "Godot で確認待ち"
                        self.logPaste("request written; waiting for confirmation result", trace: trace)
                        connection.receive(minimumIncompleteLength: 4096, maximumLength: 4096) { data, _, _, error in
                            self.finishSend(connection, data: data, error: error)
                        }
                    })
                case .waiting(let error):
                    self.logPaste("connection waiting: \(error)", trace: trace)
                case .failed(let error):
                    self.finishSend(connection, error: error)
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
                guard let connection, self?.sentMap == nil else { return }
                self?.finishSend(connection, error: MapError("Godot から応答がありません。対象ステージを開き、MapEdit プラグインを確認してください。"))
            }
        } catch {
            logPaste("send preparation failed: \(error.localizedDescription)")
            show(error)
        }
    }

    private func logPaste(_ message: String, trace: String = "-") {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [MapEditPaste] [\(trace)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func finishSend(_ connection: NWConnection, data: Data? = nil, error: Error? = nil) {
        guard pasteConnection === connection else { return }
        pasteConnection = nil
        defer { sentMap = nil; sentMapID = nil }
        connection.stateUpdateHandler = nil
        connection.cancel()
        do {
            if let error { throw error }
            guard let data, !data.isEmpty else { throw MapError("Godot から応答がありません。") }
            logPaste("reply received bytes=\(data.count)", trace: pasteTrace)
            let response = try JSONDecoder().decode(PasteResponse.self, from: data)
            logPaste("reply status=\(response.status) message=\(response.message)", trace: pasteTrace)
            switch response.status {
            case "applied":
                recordAppliedSource()
                status.stringValue = "Godot に反映しました"
            case "partial": status.stringValue = "チェックポイントを反映しました"
            case "canceled": status.stringValue = "貼り付けをキャンセルしました"
            case "unchanged":
                recordAppliedSource()
                status.stringValue = "変更はありません"
            default:
                status.stringValue = "貼り付けできませんでした"
                show(MapError(response.message))
            }
        } catch {
            logPaste("send failed: \(error)", trace: pasteTrace)
            status.stringValue = "送信できませんでした"
            show(MapError("Godot に送信できませんでした。対象ステージと MapEdit プラグインを確認してください。\n\(error.localizedDescription)"))
        }
    }

    private func recordAppliedSource() {
        guard sentMapID == loadedMapID, let sentMap, var current = canvas.document else { return }
        let source = SourcePlacements(cells: sentMap.cells, markers: sentMap.markers, movingPlatforms: sentMap.movingPlatforms)
        current.source = source
        if let baseline, var saved = try? JSONDecoder().decode(MapDocument.self, from: baseline) {
            saved.source = source
            self.baseline = try? encode(saved)
        }
        canvas.document = current
        refreshTitle()
        logPaste("updated comparison source from confirmed send", trace: pasteTrace)
    }

    @objc private func pasteMap() {
        do {
            guard let value = NSPasteboard.general.string(forType: .string) else {
                throw MapError("クリップボードに配置データがありません。")
            }
            try replace(with: Data(value.utf8), file: nil)
        } catch { show(error) }
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try replace(with: Data(contentsOf: url), file: url) } catch { show(error) }
    }

    @objc private func save() { _ = write(choosingFile: false) }
    @objc private func saveAs() { _ = write(choosingFile: true) }

    private func write(choosingFile: Bool) -> Bool {
        guard let map = canvas.document else { return false }
        var target = choosingFile ? nil : file
        if target == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "placements.mapedit.json"
            guard panel.runModal() == .OK else { return false }
            target = panel.url
        }
        guard let target else { return false }
        do {
            try map.validate()
            let data = try encode(map)
            try data.write(to: target, options: .atomic)
            baseline = data
            file = target
            refreshTitle()
            return true
        } catch {
            show(error)
            return false
        }
    }

    private func allowReplacement() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "編集中の配置を保存しますか？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "破棄")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return write(choosingFile: false)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func sessionURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false)
            .appendingPathComponent("BungeeGumMapEdit", isDirectory: true)
            .appendingPathComponent("session.json")
    }

    private func restoreSession() {
        do {
            let url = try sessionURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let session = try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: url))
            try session.map.validate()
            var map = session.map
            map.cells.sort(by: Placement.ordered)
            let file = session.file.flatMap { url in
                url.isFileURL && FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            var baseline = session.baseline
            if map.source == nil, session.file == nil, let saved = baseline,
               var original = try? JSONDecoder().decode(MapDocument.self, from: saved),
               original.stage == map.stage, original.base == map.base {
                let source = SourcePlacements(cells: original.cells, markers: original.markers, movingPlatforms: original.movingPlatforms)
                map.source = source
                original.source = source
                baseline = try encode(original)
            }
            load(map, file: file, baseline: baseline, camera: session.camera)
        } catch {
            show(MapError("前回の作業を復元できませんでした。Godotからステージをコピーし直してください。\n\(error.localizedDescription)"))
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let map = canvas.document else { return .terminateNow }
        do {
            try map.validate()
            let url = try sessionURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let session = SavedSession(map: map, baseline: baseline, file: file, camera: canvas.camera)
            try JSONEncoder().encode(session).write(to: url, options: .atomic)
            return .terminateNow
        } catch {
            show(MapError("作業を自動保存できませんでした。\n\(error.localizedDescription)"))
            return .terminateCancel
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender !== window {
            styleColor.deactivate()
            styleOutlineColor.deactivate()
            styleKind = nil
            return true
        }
        NSApp.terminate(nil)
        return false
    }
}

let app = NSApplication.shared
let editor = MapEdit()
app.setActivationPolicy(.regular)
app.delegate = editor
app.run()
