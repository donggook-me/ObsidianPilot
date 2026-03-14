import Foundation

class VaultService: ObservableObject {
    var vaultPath: String

    private let excludedDirs: Set<String> = [".obsidian", ".claude", ".trash", ".git", "node_modules"]

    init(vaultPath: String) {
        self.vaultPath = vaultPath
    }

    // MARK: - Category Discovery

    /// Vault 최상위 폴더를 카테고리로 감지
    func discoverCategories() -> [VaultCategoryInfo] {
        guard !vaultPath.isEmpty else { return [] }
        let fm = FileManager.default
        let root = URL(fileURLWithPath: vaultPath)

        guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var categories: [VaultCategoryInfo] = []

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let name = url.lastPathComponent
            // 숨김 폴더 및 제외 폴더 스킵
            if name.hasPrefix(".") || excludedDirs.contains(name.lowercased()) { continue }
            // Templates 등 대소문자 무관 제외
            if excludedDirs.contains(name) { continue }

            let count = countMarkdownFiles(in: url)
            if count > 0 {
                categories.append(VaultCategoryInfo(name: name, fileCount: count))
            }
        }

        return categories.sorted { $0.fileCount > $1.fileCount }
    }

    /// 카테고리 이름 목록 (organize 등에서 사용)
    func categoryNames() -> [String] {
        discoverCategories().map { $0.name }
    }

    // MARK: - File Discovery

    func recentFiles(hours: Int = 24) -> [VaultFile] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        return allMarkdownFiles().filter { $0.modifiedDate > cutoff }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    func allMarkdownFiles() -> [VaultFile] {
        let root = URL(fileURLWithPath: vaultPath)
        var files: [VaultFile] = []

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let relativePath = url.path.replacingOccurrences(of: vaultPath + "/", with: "")

            // Skip excluded directories
            let topDir = relativePath.components(separatedBy: "/").first ?? ""
            if excludedDirs.contains(topDir) || excludedDirs.contains(topDir.lowercased()) {
                enumerator.skipDescendants()
                continue
            }

            guard url.pathExtension == "md" else { continue }

            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }

            let modDate = resourceValues?.contentModificationDate ?? Date.distantPast
            let category = detectCategory(relativePath: relativePath)

            files.append(VaultFile(
                name: url.deletingPathExtension().lastPathComponent,
                relativePath: relativePath,
                fullPath: url.path,
                category: category,
                modifiedDate: modDate
            ))
        }

        return files.sorted { $0.modifiedDate > $1.modifiedDate }
    }

    func filesInCategory(_ category: String) -> [VaultFile] {
        allMarkdownFiles().filter { $0.category == category }
    }

    // MARK: - Category Detection

    private func detectCategory(relativePath: String) -> String {
        let topDir = relativePath.components(separatedBy: "/").first ?? ""
        // 최상위에 있는 파일은 "root"
        if !relativePath.contains("/") { return "root" }
        return topDir
    }

    // MARK: - File Content

    func readFile(_ file: VaultFile) -> String? {
        try? String(contentsOfFile: file.fullPath, encoding: .utf8)
    }

    // MARK: - Helpers

    private func countMarkdownFiles(in dir: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "md" {
            count += 1
        }
        return count
    }
}
