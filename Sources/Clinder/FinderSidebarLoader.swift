import CoreServices
import Foundation

@_silgen_name("LSSharedFileListCreate")
private func SFLCreate(_ allocator: CFAllocator?, _ listType: CFString, _ options: CFDictionary?) -> Unmanaged<LSSharedFileList>?

@_silgen_name("LSSharedFileListCopySnapshot")
private func SFLCopySnapshot(_ list: LSSharedFileList, _ seed: UnsafeMutablePointer<UInt32>?) -> Unmanaged<CFArray>?

@_silgen_name("LSSharedFileListItemCopyDisplayName")
private func SFLItemCopyDisplayName(_ item: LSSharedFileListItem) -> Unmanaged<CFString>

@_silgen_name("LSSharedFileListItemCopyResolvedURL")
private func SFLItemCopyResolvedURL(_ item: LSSharedFileListItem, _ flags: UInt32, _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

enum FinderSidebarLoader {
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
        return places.isEmpty ? fallbackPlaces() : places
    }

    private static func appendLocations(to places: inout [Place], seen: inout Set<String>) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloudDrive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
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

        let fallbackSection = volumeItems.isEmpty && !hasICloud ? "Locations" : nil
        append(Place(name: "AirDrop", symbol: "airdrop", url: nil, section: fallbackSection), to: &places, seen: &seen)
        append(Place(name: "Network", symbol: "network", url: URL(fileURLWithPath: "/Network")), to: &places, seen: &seen)
        append(Place(name: "Trash", symbol: "trash", url: home.appendingPathComponent(".Trash")), to: &places, seen: &seen)
    }

    private static func topPlace(from item: SidebarItem) -> Place {
        let name = normalizedTopName(item.displayName)
        switch name {
        case "Recents":
            return Place(name: "Recents", symbol: "clock", url: nil)
        case "Shared":
            return Place(name: "Shared", symbol: "shared.with.you", url: nil)
        default:
            return Place(name: name, symbol: symbol(for: name, url: item.url), url: item.url)
        }
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
