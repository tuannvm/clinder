import AppKit
import CoreServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate, NSSplitViewDelegate {
    private var panel: NSPanel!
    private let splitView = NSSplitView()
    private let sidebar = NSStackView()
    private var sidebarButtons: [NSButton] = []
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let navigationControl = NavigationControl()
    private let tableView = ContextTableView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private var currentURL = FileManager.default.homeDirectoryForCurrentUser
    private var hasLoadedFolder = false
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var cutItemURLs: [URL] = []
    private var visualSelectionAnchorRow: Int?
    private var isProgrammaticSelectionChange = false
    private var allItems: [FileItem] = []
    private var visibleItems: [FileItem] = []
    private var places: [Place] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        loadFolder(currentURL)
        showPanel()
        DispatchQueue.main.async { [weak self] in
            self?.focusFileList()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.focusFileList()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.isMovableByWindowBackground = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        configureWindowToolbar()

        let root = NSView()
        root.identifier = NSUserInterfaceItemIdentifier("root")
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root

        let background = NSView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(background)

        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        root.addSubview(splitView)

        let sidebarContainer = NSView()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.wantsLayer = true
        sidebarContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 4
        sidebar.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 16, right: 12)
        sidebarContainer.addSubview(sidebar)
        buildSidebar()

        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false
        main.setContentHuggingPriority(.defaultLow, for: .horizontal)
        main.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buildMainArea(in: main)

        splitView.addArrangedSubview(sidebarContainer)
        splitView.addArrangedSubview(main)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            background.topAnchor.constraint(equalTo: root.topAnchor),
            background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: root.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebar.bottomAnchor.constraint(lessThanOrEqualTo: sidebarContainer.bottomAnchor)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.splitView.setPosition(220, ofDividerAt: 0)
        }

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
            if self.handleVimKey(event) {
                return nil
            }
            return event
        }
    }

    private func configureWindowToolbar() {
        configureNavigationControl()

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        searchField.placeholderString = "Search"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.controlSize = .regular
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self

        let toolbar = NSToolbar(identifier: .clinderToolbar)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        panel.toolbar = toolbar

        if #available(macOS 11.0, *) {
            panel.toolbarStyle = .unifiedCompact
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.clinderNavigation, .flexibleSpace, .clinderTitle, .flexibleSpace, .clinderSearch]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .clinderNavigation:
            item.view = navigationControl
            item.paletteLabel = "Navigation"
        case .clinderTitle:
            item.view = titleLabel
            item.paletteLabel = "Folder"
        case .clinderSearch:
            item.view = searchField
            item.paletteLabel = "Search"
        default:
            return nil
        }
        return item
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        160
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let mainMinimumWidth: CGFloat = 520
        let maximumSidebarWidth = min(CGFloat(360), splitView.bounds.width - mainMinimumWidth)
        return max(220, maximumSidebarWidth)
    }

    private func buildSidebar() {
        places = FinderSidebarLoader.loadPlaces()
        var currentSection: String?
        for (index, place) in places.enumerated() {
            if place.section != currentSection {
                currentSection = place.section
                if let section = currentSection {
                    let label = NSTextField(labelWithString: section)
                    label.translatesAutoresizingMaskIntoConstraints = false
                    label.font = .systemFont(ofSize: 11, weight: .semibold)
                    label.textColor = .secondaryLabelColor
                    sidebar.addArrangedSubview(label)
                    label.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -26).isActive = true
                    if sidebar.arrangedSubviews.count > 1 {
                        label.topAnchor.constraint(equalTo: sidebar.arrangedSubviews[sidebar.arrangedSubviews.count - 2].bottomAnchor, constant: 12).isActive = true
                    }
                }
            }

            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.title = place.name
            button.image = NSImage(systemSymbolName: place.symbol, accessibilityDescription: place.name)
            button.imagePosition = .imageLeading
            button.alignment = .left
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.target = self
            button.action = #selector(selectPlace(_:))
            button.tag = index
            button.contentTintColor = .labelColor
            sidebar.addArrangedSubview(button)
            sidebarButtons.append(button)
            button.widthAnchor.constraint(equalTo: sidebar.widthAnchor, constant: -26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        updateSelectedPlace(index: places.firstIndex { $0.url == FileManager.default.homeDirectoryForCurrentUser })
    }

    private func buildMainArea(in main: NSView) {
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClickItem(_:))
        panel.initialFirstResponder = tableView

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 380
        nameColumn.minWidth = 220
        tableView.addTableColumn(nameColumn)

        let modifiedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("modified"))
        modifiedColumn.title = "Date Modified"
        modifiedColumn.width = 200
        tableView.addTableColumn(modifiedColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 100
        tableView.addTableColumn(sizeColumn)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.width = 130
        tableView.addTableColumn(kindColumn)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let shortcutStrip = NSView()
        shortcutStrip.translatesAutoresizingMaskIntoConstraints = false
        shortcutStrip.wantsLayer = true
        shortcutStrip.layer?.cornerRadius = 6
        shortcutStrip.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.lineBreakMode = .byTruncatingTail
        shortcutStrip.addSubview(shortcutLabel)

        main.addSubview(scrollView)
        main.addSubview(shortcutStrip)

        NSLayoutConstraint.activate([
            navigationControl.widthAnchor.constraint(equalToConstant: 66),
            navigationControl.heightAnchor.constraint(equalToConstant: 28),
            searchField.widthAnchor.constraint(equalToConstant: 230),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            scrollView.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: main.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: shortcutStrip.topAnchor, constant: -6),
            shortcutStrip.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 10),
            shortcutStrip.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -10),
            shortcutStrip.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -10),
            shortcutStrip.heightAnchor.constraint(equalToConstant: 24),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutStrip.leadingAnchor, constant: 12),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutStrip.trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutStrip.centerYAnchor)
        ])
        updateNavigationButtons()
        updateShortcutHint()
    }

    private func configureNavigationControl() {
        navigationControl.translatesAutoresizingMaskIntoConstraints = false
        navigationControl.onBack = { [weak self] in
            self?.goBack()
        }
        navigationControl.onForward = { [weak self] in
            self?.goForward()
        }
        navigationControl.toolTip = "Back / Forward"
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
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        panel.makeMain()
        focusFileList()
    }

    private func focusFileList() {
        panel.makeFirstResponder(tableView)
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
        let rawOrigin = NSPoint(
            x: visibleFrame.midX - panelFrame.width / 2,
            y: visibleFrame.midY - panelFrame.height / 2
        )
        panel.setFrameOrigin(pixelAligned(rawOrigin, on: screen))
    }

    private func pixelAligned(_ point: NSPoint, on screen: NSScreen) -> NSPoint {
        let scale = screen.backingScaleFactor
        return NSPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
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
        visualSelectionAnchorRow = nil
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

    private func handleVimKey(_ event: NSEvent) -> Bool {
        guard !isSearchFieldActive else { return false }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        guard let rawKey = event.charactersIgnoringModifiers, rawKey.count == 1 else { return false }
        let key = rawKey.lowercased()

        switch key {
        case "/":
            focusSearch()
        case "j":
            moveSelectionBy(1)
        case "k":
            moveSelectionBy(-1)
        case "g" where rawKey == "G":
            selectLastRow()
        case "g":
            selectFirstRow()
        case "h":
            goBack()
        case "l":
            openSelectedItem()
        case "v":
            toggleVisualSelection()
        case "y":
            copySelectedFiles()
        case "d":
            trashSelectedFiles()
        case "p":
            pasteFiles()
        case "x":
            cutSelectedFiles()
        default:
            return false
        }
        return true
    }

    private var isSearchFieldActive: Bool {
        guard let firstResponder = panel.firstResponder else { return false }
        if firstResponder === searchField.currentEditor() {
            return true
        }
        return searchField.currentEditor() === firstResponder
    }

    private func focusSearch() {
        panel.makeFirstResponder(searchField)
    }

    private func moveSelectionBy(_ delta: Int) {
        guard !visibleItems.isEmpty else { return }
        let currentRow = tableView.selectedRow >= 0 ? tableView.selectedRow : (delta > 0 ? -1 : visibleItems.count)
        let nextRow = min(max(currentRow + delta, 0), visibleItems.count - 1)

        if let anchor = visualSelectionAnchorRow {
            selectRows(anchor...nextRow)
        } else {
            selectRows(nextRow...nextRow)
        }
        tableView.scrollRowToVisible(nextRow)
    }

    private func selectFirstRow() {
        guard !visibleItems.isEmpty else { return }
        visualSelectionAnchorRow = nil
        selectRows(0...0)
        tableView.scrollRowToVisible(0)
    }

    private func selectLastRow() {
        guard !visibleItems.isEmpty else { return }
        let lastRow = visibleItems.count - 1
        visualSelectionAnchorRow = nil
        selectRows(lastRow...lastRow)
        tableView.scrollRowToVisible(lastRow)
    }

    private func toggleVisualSelection() {
        if visualSelectionAnchorRow != nil {
            visualSelectionAnchorRow = nil
        } else {
            let row = tableView.selectedRow >= 0 ? tableView.selectedRow : min(0, visibleItems.count - 1)
            guard row >= 0 else { return }
            visualSelectionAnchorRow = row
            selectRows(row...row)
        }
        updateShortcutHint()
    }

    private func selectRows(_ range: ClosedRange<Int>) {
        let lower = max(min(range.lowerBound, range.upperBound), 0)
        let upper = min(max(range.lowerBound, range.upperBound), visibleItems.count - 1)
        guard lower <= upper else { return }

        isProgrammaticSelectionChange = true
        tableView.selectRowIndexes(IndexSet(integersIn: lower...upper), byExtendingSelection: false)
        isProgrammaticSelectionChange = false
        updateShortcutHint()
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = !backStack.isEmpty
        forwardButton.isEnabled = !forwardStack.isEmpty
        navigationControl.canGoBack = !backStack.isEmpty
        navigationControl.canGoForward = !forwardStack.isEmpty
    }

    private func updateSelectedPlace(index selectedIndex: Int?) {
        for (index, button) in sidebarButtons.enumerated() {
            let isSelected = index == selectedIndex
            button.contentTintColor = .labelColor
            button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isSelected ? .semibold : .regular)
            button.layer?.backgroundColor = isSelected
                ? NSColor.quaternaryLabelColor.withAlphaComponent(0.22).cgColor
                : NSColor.clear.cgColor
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
        visualSelectionAnchorRow = nil
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
        visualSelectionAnchorRow = nil
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
        if !isProgrammaticSelectionChange {
            visualSelectionAnchorRow = nil
        }
        updateShortcutHint()
    }

    private func updateShortcutHint() {
        let selectedCount = selectedItems().count
        let hasSelection = selectedCount > 0
        let canPaste = !cutItemURLs.isEmpty || !pasteboardFileURLs().isEmpty
        if hasSelection {
            let prefix: String
            if visualSelectionAnchorRow != nil {
                prefix = "VISUAL \(selectedCount)"
            } else {
                prefix = selectedCount == 1 ? "Return/l Open" : "\(selectedCount) selected"
            }
            shortcutLabel.stringValue = canPaste
                ? "\(prefix)   j/k Move   v Select   y Yank   x Cut   d Trash   p Paste   ⌥⌘C Path"
                : "\(prefix)   j/k Move   v Select   y Yank   x Cut   d Trash   ⌥⌘C Path"
        } else {
            shortcutLabel.stringValue = canPaste
                ? "j/k Move   v Select   p Paste   / Search   or press ⌘V to paste here"
                : "j/k Move   v Select   y Yank   d Trash   / Search"
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
        case "size":
            return item.sizeText
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

private extension NSToolbar.Identifier {
    static let clinderToolbar = NSToolbar.Identifier("dev.tuannvm.clinder.toolbar")
}

private extension NSToolbarItem.Identifier {
    static let clinderNavigation = NSToolbarItem.Identifier("dev.tuannvm.clinder.toolbar.navigation")
    static let clinderTitle = NSToolbarItem.Identifier("dev.tuannvm.clinder.toolbar.title")
    static let clinderSearch = NSToolbarItem.Identifier("dev.tuannvm.clinder.toolbar.search")
}

@_silgen_name("LSSharedFileListCreate")
private func SFLCreate(_ allocator: CFAllocator?, _ listType: CFString, _ options: CFDictionary?) -> Unmanaged<LSSharedFileList>?

@_silgen_name("LSSharedFileListCopySnapshot")
private func SFLCopySnapshot(_ list: LSSharedFileList, _ seed: UnsafeMutablePointer<UInt32>?) -> Unmanaged<CFArray>?

@_silgen_name("LSSharedFileListItemCopyDisplayName")
private func SFLItemCopyDisplayName(_ item: LSSharedFileListItem) -> Unmanaged<CFString>

@_silgen_name("LSSharedFileListItemCopyResolvedURL")
private func SFLItemCopyResolvedURL(_ item: LSSharedFileListItem, _ flags: UInt32, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

private enum FinderSidebarLoader {
    private static let topSidebarList = "com.apple.LSSharedFileList.TopSidebarSection"
    private static let favoritesList = "com.apple.LSSharedFileList.FavoriteItems"
    private static let favoriteVolumesList = "com.apple.LSSharedFileList.FavoriteVolumes"
    private static let iCloudList = "com.apple.LSSharedFileList.iCloudItems"

    static func loadPlaces() -> [Place] {
        var places: [Place] = []
        var seen = Set<String>()

        let topItems = readList(topSidebarList)
        if topItems.isEmpty {
            append(Place(name: "Recents", symbol: "clock", url: nil), to: &places, seen: &seen)
            append(Place(name: "Shared", symbol: "shared.with.you", url: nil), to: &places, seen: &seen)
        } else {
            for item in topItems {
                append(topPlace(from: item), to: &places, seen: &seen)
            }
        }

        for item in readList(favoritesList) {
            guard let url = item.url else { continue }
            append(
                Place(name: item.displayName, symbol: symbol(for: item.displayName, url: url), url: url, section: "Favorites"),
                to: &places,
                seen: &seen
            )
        }

        appendLocations(to: &places, seen: &seen)

        if places.isEmpty {
            return fallbackPlaces()
        }
        return places
    }

    private static func appendLocations(to places: inout [Place], seen: inout Set<String>) {
        let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let hasICloud = !readList(iCloudList).isEmpty || FileManager.default.fileExists(atPath: iCloudDrive.path)
        if hasICloud {
            append(Place(name: "iCloud Drive", symbol: "icloud", url: iCloudDrive, section: "Locations"), to: &places, seen: &seen)
        }

        let volumeItems = readList(favoriteVolumesList)
        for item in volumeItems {
            guard let url = item.url, !item.displayName.isEmpty else { continue }
            append(
                Place(name: item.displayName, symbol: symbol(for: item.displayName, url: url), url: url, section: "Locations"),
                to: &places,
                seen: &seen
            )
        }

        append(Place(name: "AirDrop", symbol: "airdrop", url: nil, section: volumeItems.isEmpty && !hasICloud ? "Locations" : nil), to: &places, seen: &seen)
        append(Place(name: "Network", symbol: "network", url: URL(fileURLWithPath: "/Network")), to: &places, seen: &seen)
        append(Place(name: "Trash", symbol: "trash", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")), to: &places, seen: &seen)
    }

    private static func topPlace(from item: SidebarItem) -> Place {
        let name = normalizedTopName(item.displayName)
        if name == "Recents" {
            return Place(name: "Recents", symbol: "clock", url: nil)
        }
        if name == "Shared" {
            return Place(name: "Shared", symbol: "shared.with.you", url: nil)
        }
        return Place(name: name, symbol: symbol(for: name, url: item.url), url: item.url)
    }

    private static func normalizedTopName(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("Shared") {
            return "Shared"
        }
        if name.localizedCaseInsensitiveContains("Recent") {
            return "Recents"
        }
        return name
    }

    private static func readList(_ listName: String) -> [SidebarItem] {
        guard let list = SFLCreate(nil, listName as CFString, nil)?.takeRetainedValue() else {
            return []
        }

        var seed: UInt32 = 0
        guard let items = SFLCopySnapshot(list, &seed)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return []
        }

        return items.compactMap { item in
            let displayName = (SFLItemCopyDisplayName(item).takeRetainedValue() as String)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedURL = SFLItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?
            guard !displayName.isEmpty || resolvedURL != nil else { return nil }
            return SidebarItem(displayName: displayName, url: resolvedURL)
        }
    }

    private static func append(_ place: Place, to places: inout [Place], seen: inout Set<String>) {
        let key = place.url?.standardizedFileURL.path ?? "builtin:\(place.name)"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        places.append(place)
    }

    private static func symbol(for name: String, url: URL?) -> String {
        let lowerName = name.lowercased()
        let path = url?.standardizedFileURL.path.lowercased() ?? ""

        if lowerName == "applications" || path == "/applications" { return "a.square" }
        if lowerName == "desktop" || path.hasSuffix("/desktop") { return "desktopcomputer" }
        if lowerName == "documents" || path.hasSuffix("/documents") { return "doc" }
        if lowerName == "downloads" || path.hasSuffix("/downloads") { return "arrow.down.circle" }
        if lowerName == "recents" { return "clock" }
        if lowerName == "shared" { return "shared.with.you" }
        if lowerName.contains("icloud") { return "icloud" }
        if lowerName.contains("google drive") || path.contains("/cloudstorage/") { return "externaldrive" }
        if lowerName == NSUserName().lowercased() || path == FileManager.default.homeDirectoryForCurrentUser.path.lowercased() { return "house" }
        if lowerName == "network" { return "network" }
        if lowerName == "trash" { return "trash" }
        return "folder"
    }

    private static func fallbackPlaces() -> [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Place(name: "Recents", symbol: "clock", url: nil),
            Place(name: "Shared", symbol: "shared.with.you", url: nil),
            Place(name: "Applications", symbol: "a.square", url: URL(fileURLWithPath: "/Applications"), section: "Favorites"),
            Place(name: "Desktop", symbol: "desktopcomputer", url: home.appendingPathComponent("Desktop")),
            Place(name: "Documents", symbol: "doc", url: home.appendingPathComponent("Documents")),
            Place(name: "Downloads", symbol: "arrow.down.circle", url: home.appendingPathComponent("Downloads")),
            Place(name: "iCloud Drive", symbol: "icloud", url: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), section: "Locations"),
            Place(name: NSUserName(), symbol: "house", url: home),
            Place(name: "AirDrop", symbol: "airdrop", url: nil),
            Place(name: "Network", symbol: "network", url: URL(fileURLWithPath: "/Network")),
            Place(name: "Trash", symbol: "trash", url: home.appendingPathComponent(".Trash"))
        ]
    }
}

private struct SidebarItem {
    let displayName: String
    let url: URL?
}

@MainActor
private final class NavigationControl: NSView {
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    var canGoBack = false {
        didSet {
            backButton.isEnabled = canGoBack
            updateTint()
        }
    }

    var canGoForward = false {
        didSet {
            forwardButton.isEnabled = canGoForward
            updateTint()
        }
    }

    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let divider = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1

        configure(button: backButton, symbol: "chevron.left", action: #selector(backClicked(_:)))
        configure(button: forwardButton, symbol: "chevron.right", action: #selector(forwardClicked(_:)))

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

        addSubview(backButton)
        addSubview(forwardButton)
        addSubview(divider)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            backButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            forwardButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            forwardButton.topAnchor.constraint(equalTo: topAnchor),
            forwardButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            forwardButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            divider.centerXAnchor.constraint(equalTo: centerXAnchor),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateTint()
    }

    private func configure(button: NSButton, symbol: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = action
        button.focusRingType = .none
    }

    private func updateTint() {
        backButton.contentTintColor = canGoBack ? .labelColor : .tertiaryLabelColor
        forwardButton.contentTintColor = canGoForward ? .labelColor : .tertiaryLabelColor
    }

    @objc private func backClicked(_ sender: NSButton) {
        guard canGoBack else { return }
        onBack?()
    }

    @objc private func forwardClicked(_ sender: NSButton) {
        guard canGoForward else { return }
        onForward?()
    }
}

private struct Place {
    let name: String
    let symbol: String
    let url: URL?
    let section: String?

    init(name: String, symbol: String, url: URL?, section: String? = nil) {
        self.name = name
        self.symbol = symbol
        self.url = url
        self.section = section
    }
}

@MainActor
private final class ContextTableView: NSTableView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

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
    let sizeText: String
    let kind: String

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        self.isHidden = url.lastPathComponent.hasPrefix(".")

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .localizedTypeDescriptionKey, .fileSizeKey])
        self.isDirectory = values?.isDirectory ?? false
        self.isPackage = values?.isPackage ?? false
        self.modifiedDate = values?.contentModificationDate ?? Date.distantPast
        if isDirectory && !isPackage {
            self.sizeText = "--"
        } else if let fileSize = values?.fileSize {
            self.sizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        } else {
            self.sizeText = "--"
        }
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
