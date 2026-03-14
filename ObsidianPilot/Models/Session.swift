import Foundation

struct Session: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let feature: String      // organize, verify, ideas, capture
    let input: String         // 어떤 요청이었는지 (카테고리, 파일명 등)
    let result: String        // Claude 응답 전문
    let isSuccess: Bool
    let durationSeconds: Int? // 소요 시간 (초)

    init(feature: String, input: String, result: String, isSuccess: Bool = true, durationSeconds: Int? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.feature = feature
        self.input = input
        self.result = result
        self.isSuccess = isSuccess
        self.durationSeconds = durationSeconds
    }

    var featureIcon: String {
        switch feature {
        case "organize": return "folder.badge.gearshape"
        case "verify": return "checkmark.shield"
        case "ideas": return "lightbulb"
        case "capture": return "square.and.pencil"
        default: return "questionmark.circle"
        }
    }

    var featureLabel: String {
        switch feature {
        case "organize": return "Organize"
        case "verify": return "Verify"
        case "ideas": return "Ideas"
        case "capture": return "Capture"
        default: return feature
        }
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var durationString: String? {
        guard let dur = durationSeconds else { return nil }
        let m = dur / 60
        let s = dur % 60
        return m > 0 ? "\(m)분 \(s)초" : "\(s)초"
    }
}
