import Foundation
import SwiftUI

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var selectedSession: Session?
    @Published var filterFeature: String = "all"

    let filters = [
        ("all", "전체", "list.bullet"),
        ("organize", "Organize", "folder.badge.gearshape"),
        ("verify", "Verify", "checkmark.shield"),
        ("ideas", "Ideas", "lightbulb"),
        ("capture", "Capture", "square.and.pencil"),
    ]

    func filteredSessions(from store: SessionStore) -> [Session] {
        if filterFeature == "all" {
            return store.sessions
        }
        return store.sessions.filter { $0.feature == filterFeature }
    }
}
