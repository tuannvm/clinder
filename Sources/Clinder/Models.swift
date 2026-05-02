import Foundation

struct Place {
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

struct FileItem: Comparable {
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

        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .fileSizeKey
        ])
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
