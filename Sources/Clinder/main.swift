import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate, NSSplitViewDelegate {
    private var panel: NSPanel!
    private let splitView = NSSplitView()
    private let sidebar = NSStackView()
    private var sidebarButtons: [SidebarButton] = []
    private let navigationControl = NavigationControl()
    private let tableView = NSTableView()
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
    private var pendingYank = false
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

        let background = DynamicBackgroundView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.fillColor = .windowBackgroundColor
        root.addSubview(background)

        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        root.addSubview(splitView)

        let sidebarContainer = DynamicBackgroundView()
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.fillColor = .controlBackgroundColor

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
            if event.modifierFlags.contains([.command, .shift]), event.charactersIgnoringModifiers == "c" {
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

            let button = SidebarButton()
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

        let shortcutStrip = DynamicBackgroundView()
        shortcutStrip.translatesAutoresizingMaskIntoConstraints = false
        shortcutStrip.layer?.cornerRadius = 6
        shortcutStrip.fillColor = .controlBackgroundColor

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

        if pendingYank {
            pendingYank = false
            if key == "p" {
                copySelectedPath()
                return true
            }
            if key == "y" {
                copySelectedFiles()
                return true
            }
        }

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
            beginYank()
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

    private func beginYank() {
        pendingYank = true
        updateShortcutHint()
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
        navigationControl.canGoBack = !backStack.isEmpty
        navigationControl.canGoForward = !forwardStack.isEmpty
    }

    private func updateSelectedPlace(index selectedIndex: Int?) {
        for (index, button) in sidebarButtons.enumerated() {
            let isSelected = index == selectedIndex
            button.contentTintColor = .labelColor
            button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isSelected ? .semibold : .regular)
            button.isSidebarSelected = isSelected
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
            if pendingYank {
                prefix = "YANK"
            } else if visualSelectionAnchorRow != nil {
                prefix = "VISUAL \(selectedCount)"
            } else {
                prefix = selectedCount == 1 ? "Return/l Open" : "\(selectedCount) selected"
            }
            shortcutLabel.stringValue = canPaste
                ? "\(prefix)   j/k Move   v Select   yy Yank   yp Path   x Cut   d Trash   p Paste"
                : "\(prefix)   j/k Move   v Select   yy Yank   yp Path   x Cut   d Trash"
        } else {
            shortcutLabel.stringValue = canPaste
                ? "j/k Move   v Select   p Paste   / Search   or press ⌘V to paste here"
                : "j/k Move   v Select   yy Yank   yp Path   d Trash   / Search"
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
