import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var panel: NSPanel!
    private let sidebar = NSStackView()
    private var sidebarButtons: [NSButton] = []
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let tableView = ContextTableView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private var currentURL = FileManager.default.homeDirectoryForCurrentUser
    private var hasLoadedFolder = false
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var cutItemURLs: [URL] = []
    private var allItems: [FileItem] = []
    private var visibleItems: [FileItem] = []

    private let places: [Place] = [
        Place(name: "Recents", symbol: "clock", url: nil),
        Place(name: "Applications", symbol: "a.square", url: URL(fileURLWithPath: "/Applications")),
        Place(name: "Desktop", symbol: "desktopcomputer", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")),
        Place(name: "Documents", symbol: "doc", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")),
        Place(name: "Claude", symbol: "folder", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")),
        Place(name: "Skills", symbol: "folder", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")),
        Place(name: "Downloads", symbol: "arrow.down.circle", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")),
        Place(name: "iCloud Drive", symbol: "icloud", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")),
        Place(name: "Home", symbol: "house", url: FileManager.default.homeDirectoryForCurrentUser)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        loadFolder(currentURL)
        showPanel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clinder"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        panel.isOpaque = false
        panel.hasShadow = true

        let root = NSView()
        root.identifier = NSUserInterfaceItemIdentifier("root")
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let visualEffect = NSVisualEffectView()
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        root.addSubview(visualEffect)

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.distribution = .fill
        content.spacing = 0
        root.addSubview(content)

        let sidebarContainer = NSView()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.wantsLayer = true
        sidebarContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 4
        sidebar.edgeInsets = NSEdgeInsets(top: 58, left: 14, bottom: 16, right: 12)
        sidebarContainer.addSubview(sidebar)
        buildSidebar()

        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false
        main.setContentHuggingPriority(.defaultLow, for: .horizontal)
        main.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buildMainArea(in: main)

        content.addArrangedSubview(sidebarContainer)
        content.addArrangedSubview(main)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: root.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarContainer.widthAnchor.constraint(equalToConstant: 220),
            sidebar.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebar.bottomAnchor.constraint(lessThanOrEqualTo: sidebarContainer.bottomAnchor)
        ])

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.panel.close()
                NSApp.terminate(nil)
                return nil
            }
            if event.modifierFlags.contains(.command), event.keyCode == 51 || event.keyCode == 117 {
                self.trashSelectedFiles()
                return nil
            }
            if event.keyCode == 36 {
                self.openSelectedItem()
                return nil
            }
            if event.modifierFlags.contains([.command, .option]), event.charactersIgnoringModifiers == "c" {
                self.copySelectedPath()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                self.copySelectedFiles()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "x" {
                self.cutSelectedFiles()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                self.pasteFiles()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "[" {
                self.goBack()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "]" {
                self.goForward()
                return nil
            }
            return event
        }
    }

    private func buildSidebar() {
        for (index, place) in places.enumerated() {
            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.title = place.name
            button.image = NSImage(systemSymbolName: place.symbol, accessibilityDescription: place.name)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.target = self
            button.action = #selector(selectPlace(_:))
            button.tag = index
            button.contentTintColor = .labelColor
            sidebar.addArrangedSubview(button)
            sidebarButtons.append(button)
            button.widthAnchor.constraint(equalToConstant: 190).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        updateSelectedPlace(index: places.firstIndex { $0.name == "Home" })
    }

    private func buildMainArea(in main: NSView) {
        let toolbar = NSStackView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY

        configureToolbarButton(backButton, symbol: "chevron.left", label: "Back", action: #selector(backClicked(_:)))
        configureToolbarButton(forwardButton, symbol: "chevron.right", label: "Forward", action: #selector(forwardClicked(_:)))

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        searchField.placeholderString = "Search"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self

        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(forwardButton)
        toolbar.addArrangedSubview(titleLabel)
        toolbar.addArrangedSubview(NSView())
        toolbar.addArrangedSubview(searchField)

        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClickItem(_:))

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 380
        nameColumn.minWidth = 220
        tableView.addTableColumn(nameColumn)

        let modifiedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        modifiedColumn.title = "Modified"
        modifiedColumn.width = 200
        tableView.addTableColumn(modifiedColumn)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.width = 130
        tableView.addTableColumn(kindColumn)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let shortcutStrip = NSVisualEffectView()
        shortcutStrip.translatesAutoresizingMaskIntoConstraints = false
        shortcutStrip.material = .hudWindow
        shortcutStrip.blendingMode = .withinWindow
        shortcutStrip.state = .active
        shortcutStrip.wantsLayer = true
        shortcutStrip.layer?.cornerRadius = 8

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.lineBreakMode = .byTruncatingTail
        shortcutStrip.addSubview(shortcutLabel)

        main.addSubview(toolbar)
        main.addSubview(scrollView)
        main.addSubview(shortcutStrip)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 18),
            toolbar.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -18),
            toolbar.topAnchor.constraint(equalTo: main.topAnchor, constant: 42),
            toolbar.heightAnchor.constraint(equalToConstant: 36),
            backButton.widthAnchor.constraint(equalToConstant: 30),
            backButton.heightAnchor.constraint(equalToConstant: 28),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),
            forwardButton.heightAnchor.constraint(equalToConstant: 28),
            searchField.widthAnchor.constraint(equalToConstant: 220),
            scrollView.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: shortcutStrip.topAnchor, constant: -8),
            shortcutStrip.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 12),
            shortcutStrip.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -12),
            shortcutStrip.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -12),
            shortcutStrip.heightAnchor.constraint(equalToConstant: 30),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutStrip.leadingAnchor, constant: 12),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutStrip.trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutStrip.centerYAnchor)
        ])
        updateNavigationButtons()
        updateShortcutHint()
    }

    private func configureToolbarButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
        button.toolTip = label
    }

    private func showPanel() {
        centerPanelOnPointerScreen()
        keepPanelVisible()
    }

    private func keepPanelVisible() {
        panel.level = .popUpMenu
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeMain()
    }

    private func keepPanelVisibleAfterMenuAction() {
        DispatchQueue.main.async { [weak self] in
            self?.keepPanelVisible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.keepPanelVisible()
        }
    }

    private func centerPanelOnPointerScreen() {
        let pointer = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            screen.frame.contains(pointer)
        } ?? NSScreen.main

        guard let screen = targetScreen else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let origin = NSPoint(
            x: visibleFrame.midX - panelFrame.width / 2,
            y: visibleFrame.midY - panelFrame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    @objc private func selectPlace(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < places.count else { return }
        updateSelectedPlace(index: sender.tag)
        let place = places[sender.tag]
        if place.name == "Recents" {
            loadRecents()
            return
        }
        guard let url = place.url else { return }
        loadFolder(url)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        applySearch(sender.stringValue)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let searchField = notification.object as? NSSearchField else { return }
        applySearch(searchField.stringValue)
    }

    @objc private func doubleClickItem(_ sender: Any) {
        openSelectedItem()
    }

    @objc private func backClicked(_ sender: NSButton) {
        goBack()
    }

    @objc private func forwardClicked(_ sender: NSButton) {
        goForward()
    }

    private func loadFolder(_ url: URL, recordHistory: Bool = true) {
        if recordHistory, hasLoadedFolder, currentURL != url {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }
        currentURL = url
        hasLoadedFolder = true
        titleLabel.stringValue = url.path == FileManager.default.homeDirectoryForCurrentUser.path ? "tuannvm" : url.lastPathComponent
        searchField.stringValue = ""

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .localizedTypeDescriptionKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        )) ?? []

        allItems = urls.map { FileItem(url: $0) }.sorted()
        visibleItems = allItems
        tableView.reloadData()
        updateNavigationButtons()
        updateSelectedPlace(for: url)
        updateShortcutHint()
    }

    private func goBack() {
        guard let destination = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        loadFolder(destination, recordHistory: false)
    }

    private func goForward() {
        guard let destination = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        loadFolder(destination, recordHistory: false)
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = !backStack.isEmpty
        forwardButton.isEnabled = !forwardStack.isEmpty
    }

    private func updateSelectedPlace(index selectedIndex: Int?) {
        for (index, button) in sidebarButtons.enumerated() {
            let isSelected = index == selectedIndex
            button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
            button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isSelected ? .semibold : .regular)
        }
    }

    private func updateSelectedPlace(for url: URL) {
        let standardizedURL = url.standardizedFileURL
        let matchingIndex = places.firstIndex { place in
            place.url?.standardizedFileURL == standardizedURL
        }
        updateSelectedPlace(index: matchingIndex)
    }

    private func loadRecents() {
        titleLabel.stringValue = "Recents"
        searchField.stringValue = ""
        let searchRoots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        ]

        var items: [FileItem] = []
        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .localizedTypeDescriptionKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator.prefix(250) {
                items.append(FileItem(url: url))
            }
        }
        allItems = items.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(100).map { $0 }
        visibleItems = allItems
        tableView.reloadData()
        updateShortcutHint()
    }

    private func applySearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            visibleItems = allItems
            tableView.reloadData()
            updateShortcutHint()
            return
        }
        visibleItems = allItems.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        tableView.reloadData()
        updateShortcutHint()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateShortcutHint()
    }

    private func updateShortcutHint() {
        let selectedCount = selectedItems().count
        let hasSelection = selectedCount > 0
        let canPaste = !cutItemURLs.isEmpty || !pasteboardFileURLs().isEmpty
        if hasSelection {
            let prefix = selectedCount == 1 ? "Return Open" : "\(selectedCount) selected"
            shortcutLabel.stringValue = canPaste
                ? "\(prefix)   ⌘C Copy   ⌥⌘C Copy Path   ⌘X Cut   ⌘⌫ Trash   ⌘V Paste"
                : "\(prefix)   ⌘C Copy   ⌥⌘C Copy Path   ⌘X Cut   ⌘⌫ Trash"
        } else {
            shortcutLabel.stringValue = canPaste
                ? "Select a file, or press ⌘V to paste here"
                : "Select a file to use keyboard actions"
        }
    }

    private func selectedItems() -> [FileItem] {
        tableView.selectedRowIndexes.compactMap { row in
            guard row >= 0, row < visibleItems.count else { return nil }
            return visibleItems[row]
        }
    }

    private func selectedItem() -> FileItem? {
        selectedItems().first
    }

    private func openSelectedItem() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        if items.count > 1 {
            items.forEach { NSWorkspace.shared.open($0.url) }
            return
        }
        let item = items[0]
        if item.isBrowsableDirectory {
            loadFolder(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func copySelectedPath() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(items.map(\.url.path).joined(separator: "\n"), forType: .string)
    }

    private func copySelectedFiles() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        cutItemURLs.removeAll()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
        updateShortcutHint()
    }

    private func cutSelectedFiles() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        cutItemURLs = items.map(\.url)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(items.map { $0.url as NSURL })
        updateShortcutHint()
    }

    private func trashSelectedFiles() {
        let items = selectedItems()
        guard !items.isEmpty else { return }

        var trashedAny = false
        for item in items {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &resultingURL)
                trashedAny = true
            } catch {
                NSSound.beep()
            }
        }

        if trashedAny {
            loadFolder(currentURL, recordHistory: false)
            updateShortcutHint()
        }
    }

    private func pasteFiles() {
        let sourceURLs = cutItemURLs.isEmpty ? pasteboardFileURLs() : cutItemURLs
        guard !sourceURLs.isEmpty else { return }

        for sourceURL in sourceURLs {
            let destinationURL = uniqueDestinationURL(for: sourceURL.lastPathComponent, in: currentURL)
            guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else { continue }
            do {
                if cutItemURLs.contains(sourceURL) {
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                } else {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                NSSound.beep()
            }
        }

        cutItemURLs.removeAll()
        loadFolder(currentURL, recordHistory: false)
        updateShortcutHint()
    }

    private func pasteboardFileURLs() -> [URL] {
        let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        return objects.compactMap { object in
            if let url = object as? URL {
                return url
            }
            return (object as? NSURL).map { $0 as URL }
        }
    }

    private func uniqueDestinationURL(for fileName: String, in folderURL: URL) -> URL {
        let destinationURL = folderURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return destinationURL
        }

        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension

        var index = 2
        while true {
            let candidateName = pathExtension.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(pathExtension)"
            let candidateURL = folderURL.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < visibleItems.count, let tableColumn else { return nil }
        let item = visibleItems[row]
        let identifier = tableColumn.identifier
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text(for: identifier, item: item))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = item.isHidden ? .secondaryLabelColor : .labelColor
        cell.addSubview(label)

        if identifier.rawValue == "name" {
            let image = NSImageView(image: NSWorkspace.shared.icon(forFile: item.url.path))
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyDown
            cell.addSubview(image)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 7)
            ])
        } else {
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6).isActive = true
        }

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func text(for identifier: NSUserInterfaceItemIdentifier, item: FileItem) -> String {
        switch identifier.rawValue {
        case "modified":
            return Self.dateFormatter.string(from: item.modifiedDate)
        case "kind":
            return item.kind
        default:
            return item.name
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct Place {
    let name: String
    let symbol: String
    let url: URL?
}

@MainActor
private final class ContextTableView: NSTableView {
    override func rightMouseDown(with event: NSEvent) {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        if clickedRow >= 0 {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
    }
}

private struct FileItem: Comparable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let modifiedDate: Date
    let kind: String

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.isHidden = url.lastPathComponent.hasPrefix(".")

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .localizedTypeDescriptionKey])
        self.isDirectory = values?.isDirectory ?? false
        self.isPackage = values?.isPackage ?? false
        self.modifiedDate = values?.contentModificationDate ?? Date.distantPast
        if url.pathExtension == "app" {
            self.kind = "Application"
        } else if isDirectory && !isPackage {
            self.kind = "Folder"
        } else {
            self.kind = values?.localizedTypeDescription ?? "File"
        }
    }

    var isBrowsableDirectory: Bool {
        isDirectory && !isPackage
    }

    static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

@main
enum ClinderApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
