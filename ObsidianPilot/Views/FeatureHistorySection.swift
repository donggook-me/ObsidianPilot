import SwiftUI

/// 각 피쳐 탭에서 해당 기능의 과거 세션 기록을 보여주는 컴포넌트
struct FeatureHistorySection: View {
    let feature: String
    @ObservedObject var sessionStore: SessionStore
    /// true이면 부모 ScrollView 안에 임베드 (내부 ScrollView 없음)
    var embedded: Bool = false
    @State private var selectedSession: Session?
    @State private var isExpanded = false

    private var sessions: [Session] {
        sessionStore.sessions.filter { $0.feature == feature }
    }

    var body: some View {
        if !sessions.isEmpty {
            VStack(spacing: 0) {
                Divider()

                // 헤더: 기록 토글
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("이전 기록")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(sessions.count)")
                            .font(.system(size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.bar)

                if isExpanded {
                    // 세션 리스트
                    VStack(spacing: 0) {
                        ForEach(sessions.prefix(10)) { session in
                            SessionRowButton(
                                session: session,
                                isSelected: selectedSession?.id == session.id,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedSession = selectedSession?.id == session.id ? nil : session
                                    }
                                }
                            )
                        }
                    }

                    // 선택된 세션의 내용
                    if let session = selectedSession {
                        VStack(spacing: 0) {
                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.input)
                                        .font(.system(size: 12, weight: .medium))
                                    HStack(spacing: 8) {
                                        Text(session.timeString)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        if let dur = session.durationString {
                                            Text(dur)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                Spacer()

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(session.result, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("결과 복사")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor))

                            MathMarkdownView(content: session.result)
                                .frame(maxHeight: 400)
                        }
                    }
                }
            }
        }
    }
}

struct SessionRowButton: View {
    let session: Session
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isSuccess ? Color.green : Color.red)
                    .frame(width: 6, height: 6)

                Text(session.input)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer()

                if let dur = session.durationString {
                    Text(dur)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(session.relativeTime)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
