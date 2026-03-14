import Foundation

@MainActor
class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []

    private let storePath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ObsidianPilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storePath = appDir.appendingPathComponent("sessions.json")
        load()
    }

    func add(_ session: Session) {
        sessions.insert(session, at: 0)
        // 최대 100개 유지
        if sessions.count > 100 {
            sessions = Array(sessions.prefix(100))
        }
        save()
    }

    func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    func clearAll() {
        sessions.removeAll()
        save()
    }

    /// 특정 기능의 평균 소요 시간 (초)
    func averageDuration(for feature: String) -> Int? {
        let durations = sessions
            .filter { $0.feature == feature && $0.isSuccess && $0.durationSeconds != nil }
            .compactMap { $0.durationSeconds }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / durations.count
    }

    /// "보통 ~N분 소요" 형태의 예상 시간 문자열
    func estimatedTimeString(for feature: String) -> String? {
        guard let avg = averageDuration(for: feature) else { return nil }
        let m = avg / 60
        let s = avg % 60
        if m > 0 {
            return "보통 ~\(m)분 소요"
        } else {
            return "보통 ~\(s)초 소요"
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: storePath, options: .atomic)
        } catch {
            print("SessionStore save error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storePath.path) else { return }
        do {
            let data = try Data(contentsOf: storePath)
            sessions = try JSONDecoder().decode([Session].self, from: data)
        } catch {
            print("SessionStore load error: \(error)")
        }
    }
}
