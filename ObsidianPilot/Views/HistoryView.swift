import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState

    private var vm: HistoryViewModel { appState.historyVM }
    private var store: SessionStore { appState.sessionStore }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Session List
            VStack(spacing: 0) {
                // Filter
                HStack {
                    Text("세션 기록")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $appState.historyVM.filterFeature) {
                        ForEach(vm.filters, id: \.0) { f in
                            Label(f.1, systemImage: f.2).tag(f.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
                .padding(12)
                .background(.bar)

                Divider()

                let sessions = vm.filteredSessions(from: store)

                if sessions.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("세션 기록이 없습니다")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(sessions, selection: $appState.historyVM.selectedSession) { session in
                        HStack(spacing: 10) {
                            Image(systemName: session.featureIcon)
                                .foregroundStyle(session.isSuccess ? .blue : .red)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.featureLabel)
                                        .font(.system(size: 12, weight: .semibold))
                                    if !session.isSuccess {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                                Text(session.input)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(session.relativeTime)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .tag(session)
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)

            Divider()

            // Right: Session Detail
            VStack(spacing: 0) {
                if let session = vm.selectedSession {
                    // Header
                    HStack {
                        Image(systemName: session.featureIcon)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(session.featureLabel): \(session.input)")
                                .font(.headline)
                            HStack(spacing: 8) {
                                Text(session.timeString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let dur = session.durationString {
                                    Text(dur)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(session.result, forType: .string)
                        } label: {
                            Label("복사", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            store.delete(session)
                            appState.historyVM.selectedSession = nil
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(.bar)

                    Divider()

                    // Content
                    MathMarkdownView(content: session.result)
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("세션을 선택하면 결과를 확인할 수 있습니다")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity)
        }
    }
}
