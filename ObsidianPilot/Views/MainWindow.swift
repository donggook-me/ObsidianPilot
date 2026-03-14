import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var activeToolTab: AppTab? = nil

    var body: some View {
        Group {
            if let tab = activeToolTab {
                // 도구 전체 화면
                toolFullScreen(tab)
            } else {
                // 메인: Capture 화면
                captureScreen
            }
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: .infinity,
               minHeight: 500, idealHeight: 600, maxHeight: .infinity)
    }

    // MARK: - Capture Screen (메인)

    private var captureScreen: some View {
        VStack(spacing: 0) {
            // 상단 Vault 요약 바
            vaultBar

            Divider()

            // 캡처 입력 영역
            captureInputArea

            // 진행 상태
            if appState.captureVM.isRunning {
                ProgressPanel(
                    progress: appState.captureVM.progress,
                    title: "분류 및 저장 중",
                    estimatedTime: appState.sessionStore.estimatedTimeString(for: "capture"),
                    onCancel: { appState.captureVM.cancel() }
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // 결과 / 최근 기록
            captureResultArea

            Spacer(minLength: 0)

            Divider()

            // 하단 도구 버튼들
            toolButtonsBar
        }
    }

    // MARK: - Vault Bar

    private var vaultBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 14))
                .foregroundStyle(.purple)

            if !appState.settings.vaultPath.isEmpty {
                let vaultName = (appState.settings.vaultPath as NSString).lastPathComponent
                Text(vaultName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                let fileCount = appState.vault.allMarkdownFiles().count
                Text("\(fileCount) notes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("vault에 저장된 마크다운 파일 수")
            }

            Spacer()

            // 실행 중 표시
            if !appState.runningTabs.isEmpty {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("\(appState.runningTabs.count) 작업 중")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Capture Input

    private var captureInputArea: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if appState.captureVM.inputText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("무엇을 기록할까요?")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                        Text("메모, 아이디어, 학습 내용 등을 입력하면 vault에 자동 분류·저장합니다")
                            .font(.system(size: 12))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $appState.captureVM.inputText)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100, maxHeight: 220)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.15))
            )

            // 저장 버튼
            HStack {
                Spacer()

                Button {
                    appState.captureVM.capture(claude: appState.claude, sessionStore: appState.sessionStore)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("저장")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    appState.captureVM.isRunning ||
                    appState.captureVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.return, modifiers: .command)
                .help("입력한 내용을 Claude가 분류하여 vault에 저장합니다 (⌘+Return)")
            }
        }
        .padding(16)
    }

    // MARK: - Capture Result

    private var captureResultArea: some View {
        Group {
            if appState.captureVM.showResult && !appState.captureVM.result.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("저장 완료")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button {
                            appState.captureVM.showResult = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.06))

                    MathMarkdownView(content: appState.captureVM.result)
                }
            } else if let error = appState.captureVM.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(16)
            } else {
                recentCaptures
            }
        }
    }

    private var recentCaptures: some View {
        let captures = appState.sessionStore.sessions
            .filter { $0.feature == "capture" }
            .prefix(5)

        return VStack(alignment: .leading, spacing: 0) {
            if !captures.isEmpty {
                HStack {
                    Text("최근 캡처")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

                ForEach(Array(captures)) { session in
                    HStack(spacing: 8) {
                        Image(systemName: session.isSuccess ? "checkmark.circle" : "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(session.isSuccess ? .green : .red)
                        Text(session.input)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(session.relativeTime)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                }
            }

            Spacer(minLength: 0)

            // Claude 상태
            ClaudeStatusPanel()
        }
    }

    // MARK: - Tool Buttons Bar (하단 큰 버튼)

    private var toolButtonsBar: some View {
        HStack(spacing: 10) {
            toolCardButton(
                icon: "folder.badge.gearshape",
                label: "정리",
                description: "파일 자동 분류",
                color: .blue,
                tab: .organize
            )
            toolCardButton(
                icon: "checkmark.shield",
                label: "검증",
                description: "내용 정확성 검토",
                color: .green,
                tab: .verify
            )
            toolCardButton(
                icon: "lightbulb",
                label: "아이디어",
                description: "지식 연결 탐색",
                color: .orange,
                tab: .ideas
            )
            toolCardButton(
                icon: "clock.arrow.circlepath",
                label: "기록",
                description: "작업 이력 보기",
                color: .purple,
                tab: .history
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func toolCardButton(icon: String, label: String, description: String, color: Color, tab: AppTab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeToolTab = tab
                appState.selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.system(size: 12, weight: .semibold))

                Text(description)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if appState.runningTabs.contains(tab) {
                ProgressView()
                    .controlSize(.mini)
                    .padding(4)
            }
        }
    }

    // MARK: - Tool Full Screen (도구 전체 화면)

    private func toolFullScreen(_ tab: AppTab) -> some View {
        VStack(spacing: 0) {
            // 상단 네비게이션 바
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeToolTab = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("캡처")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

                Divider()
                    .frame(height: 16)

                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(toolColor(for: tab))

                Text(tab.shortLabel)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                // 실행 중 표시
                if appState.runningTabs.contains(tab) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("작업 중")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // 도구 내용
            Group {
                switch tab {
                case .organize:
                    OrganizeView()
                case .verify:
                    VerifyView()
                case .ideas:
                    IdeaView()
                case .history:
                    HistoryView()
                case .capture:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toolColor(for tab: AppTab) -> Color {
        switch tab {
        case .organize: return .blue
        case .verify: return .green
        case .ideas: return .orange
        case .history: return .purple
        case .capture: return Color.accentColor
        }
    }
}
