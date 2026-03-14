import Foundation

struct VaultFile: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String
    let fullPath: String
    let category: String   // 동적 카테고리 (폴더명)
    let modifiedDate: Date

    var displayName: String {
        name.replacingOccurrences(of: ".md", with: "")
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: modifiedDate, relativeTo: Date())
    }
}

/// Vault에서 감지된 카테고리 정보
struct VaultCategoryInfo: Identifiable, Hashable {
    let name: String       // 폴더명 (예: "work", "math")
    let fileCount: Int
    var id: String { name }

    var icon: String {
        Self.iconFor(name)
    }

    var color: String {
        Self.colorFor(name)
    }

    /// 폴더명에서 아이콘 자동 추론 (키워드 기반, 특정 vault에 종속되지 않음)
    static func iconFor(_ name: String) -> String {
        let lower = name.lowercased()
        // 일반적인 Obsidian 폴더 패턴 매핑
        let patterns: [(keywords: [String], icon: String)] = [
            (["work", "업무", "job", "career"], "briefcase"),
            (["project", "프로젝트"], "hammer"),
            (["math", "수학", "formula"], "function"),
            (["invest", "finance", "금융", "투자", "stock", "market"], "chart.line.uptrend.xyaxis"),
            (["book", "reading", "독서", "책"], "book"),
            (["bridge", "연결", "link", "connection"], "link"),
            (["daily", "일지", "diary", "일기"], "calendar"),
            (["journal", "저널", "log"], "note.text"),
            (["reference", "참고", "ref", "resource"], "books.vertical"),
            (["template", "템플릿", "snippet"], "doc.on.doc"),
            (["archive", "보관", "old", "backup"], "archivebox"),
            (["personal", "개인", "private", "me"], "person"),
            (["note", "inbox", "메모", "scratch"], "tray.and.arrow.down"),
            (["idea", "아이디어", "brainstorm"], "lightbulb"),
            (["learn", "study", "학습", "공부", "course"], "graduationcap"),
            (["code", "dev", "개발", "programming", "tech"], "chevron.left.forwardslash.chevron.right"),
            (["design", "디자인", "ui", "ux"], "paintbrush"),
            (["health", "건강", "fitness", "운동"], "heart"),
            (["travel", "여행", "trip"], "airplane"),
            (["recipe", "요리", "food", "cook"], "fork.knife"),
            (["music", "음악"], "music.note"),
            (["photo", "사진", "image", "media"], "photo"),
            (["writing", "글쓰기", "blog", "essay", "draft"], "pencil.and.outline"),
            (["meeting", "회의", "minutes"], "person.3"),
            (["research", "연구", "paper"], "magnifyingglass"),
        ]
        for pattern in patterns {
            if pattern.keywords.contains(where: { lower.contains($0) }) {
                return pattern.icon
            }
        }
        return "folder"
    }

    /// 폴더명에서 색상 자동 추론 (키워드 기반)
    static func colorFor(_ name: String) -> String {
        let lower = name.lowercased()
        let patterns: [(keywords: [String], color: String)] = [
            (["work", "업무", "job", "project", "프로젝트"], "blue"),
            (["math", "수학", "learn", "study", "학습", "research", "연구"], "purple"),
            (["invest", "finance", "금융", "투자", "stock"], "green"),
            (["book", "reading", "독서", "책"], "orange"),
            (["bridge", "연결", "link", "connection"], "teal"),
            (["idea", "아이디어", "brainstorm"], "yellow"),
            (["code", "dev", "개발", "tech"], "indigo"),
            (["personal", "개인", "health", "건강"], "pink"),
            (["daily", "journal", "diary", "일지"], "mint"),
        ]
        for pattern in patterns {
            if pattern.keywords.contains(where: { lower.contains($0) }) {
                return pattern.color
            }
        }
        return "gray"
    }
}
