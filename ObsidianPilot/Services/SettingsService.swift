import Foundation
import SwiftUI

class SettingsService: ObservableObject {
    private static let vaultPathKey = "vaultPath"
    private static let claudePathKey = "claudePath"
    private static let onboardedKey = "isOnboarded"

    @Published var vaultPath: String {
        didSet { UserDefaults.standard.set(vaultPath, forKey: Self.vaultPathKey) }
    }

    @Published var claudePath: String {
        didSet { UserDefaults.standard.set(claudePath, forKey: Self.claudePathKey) }
    }

    @Published var isOnboarded: Bool {
        didSet { UserDefaults.standard.set(isOnboarded, forKey: Self.onboardedKey) }
    }

    init() {
        // 이전 Bundle ID에서 마이그레이션
        Self.migrateIfNeeded()

        self.isOnboarded = UserDefaults.standard.bool(forKey: Self.onboardedKey)
        self.vaultPath = UserDefaults.standard.string(forKey: Self.vaultPathKey) ?? ""
        self.claudePath = UserDefaults.standard.string(forKey: Self.claudePathKey)
            ?? Self.detectClaudePath()
    }

    private static let migrationKey = "didMigrateFromLegacy"
    private static let legacyBundleIds = ["com.dongguk.ObsidianPilot"]

    private static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        for bundleId in legacyBundleIds {
            guard let legacyDefaults = UserDefaults(suiteName: bundleId) else { continue }
            // vaultPath
            if let vault = legacyDefaults.string(forKey: vaultPathKey), !vault.isEmpty,
               UserDefaults.standard.string(forKey: vaultPathKey) == nil {
                UserDefaults.standard.set(vault, forKey: vaultPathKey)
            }
            // claudePath
            if let claude = legacyDefaults.string(forKey: claudePathKey), !claude.isEmpty,
               UserDefaults.standard.string(forKey: claudePathKey) == nil {
                UserDefaults.standard.set(claude, forKey: claudePathKey)
            }
            // isOnboarded
            if legacyDefaults.bool(forKey: onboardedKey) {
                UserDefaults.standard.set(true, forKey: onboardedKey)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Claude CLI 경로 자동 감지
    static func detectClaudePath() -> String {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // which claude 시도
        if let result = try? shellOutput("which claude"), !result.isEmpty {
            return result
        }
        return ""
    }

    /// Vault 경로가 유효한지 확인
    static func isValidVault(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return false }
        // .obsidian 폴더 또는 .md 파일이 있으면 vault로 판단
        let hasObsidian = fm.fileExists(atPath: (path as NSString).appendingPathComponent(".obsidian"))
        let hasMd = (try? fm.contentsOfDirectory(atPath: path))?.contains(where: { $0.hasSuffix(".md") }) ?? false
        return hasObsidian || hasMd
    }

    /// Claude CLI가 유효한지 확인
    static func isValidClaude(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private static func shellOutput(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
