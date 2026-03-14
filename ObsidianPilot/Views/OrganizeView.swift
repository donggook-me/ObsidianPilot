import SwiftUI
import MarkdownUI

struct OrganizeView: View {
    @EnvironmentObject var appState: AppState

    private var vm: OrganizeViewModel { appState.organizeVM }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar — 카테고리 선택 + 실행 (핵심 UI)
            // (카테고리 미로드 시 자동 로드)
            HStack(spacing: 12) {
                Text("카테고리")
                    .font(.headline)

                Picker("", selection: $appState.organizeVM.selectedCategory) {
                    ForEach(vm.categories, id: \.0) { cat in
                        Label(cat.1, systemImage: cat.2).tag(cat.0)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)

                Button {
                    vm.run(claude: appState.claude, sessionStore: appState.sessionStore)
                } label: {
                    Label("실행", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isRunning)

                Spacer()

                // 후속 지시 토글 (결과가 있을 때만)
                if !vm.result.isEmpty && !vm.isRunning {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.organizeVM.showFollowUp.toggle()
                        }
                    } label: {
                        Label(
                            vm.showFollowUp ? "후속 지시 닫기" : "후속 지시",
                            systemImage: vm.showFollowUp ? "chevron.down" : "text.bubble"
                        )
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // 메인 콘텐츠
            if vm.isRunning {
                ProgressPanel(
                    progress: vm.progress,
                    title: "Organize 진행 중",
                    estimatedTime: appState.sessionStore.estimatedTimeString(for: "organize"),
                    onCancel: { vm.cancel() }
                )
                .padding()
                Spacer()
            } else {
                if let error = vm.error {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("오류 발생")
                            .font(.headline)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else if vm.result.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Organize")
                            .font(.title2)
                        Text("상단에서 카테고리를 선택한 후 '실행' 버튼을 누르세요.\nClaude가 vault의 파일을 분석하여 자동으로 정리합니다.\n\n• 자동: 최근 24시간 내 변경된 파일을 정리\n• 전체 스캔: vault 전체를 분석\n• 카테고리: 특정 폴더의 파일만 정리")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    // 결과 + 후속 지시 패널
                    resultWithFollowUp
                }

                FeatureHistorySection(
                    feature: "organize",
                    sessionStore: appState.sessionStore
                )
            }
        }
        .onAppear {
            if vm.detectedCategories.isEmpty {
                vm.loadCategories(vault: appState.vault)
            }
        }
    }

    // MARK: - 결과 + 후속 지시

    private var resultWithFollowUp: some View {
        VStack(spacing: 0) {
            // 정리 결과 (메인)
            MathMarkdownView(content: vm.result)

            // 후속 지시 패널 (접이식)
            if vm.showFollowUp {
                Divider()
                followUpPanel
            }
        }
    }

    // MARK: - 후속 지시 패널

    private var followUpPanel: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text("후속 지시")
                    .font(.system(size: 13, weight: .semibold))
                Text("— 미해결 항목에 대해 추가 지시를 내릴 수 있습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.06))

            // 후속 대화 히스토리 (간결하게)
            if !vm.followUpHistory.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.followUpHistory) { entry in
                            followUpEntry(entry)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 200)
            }

            // 입력
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    // Placeholder (TextEditor가 비었을 때만)
                    if vm.followUpInput.isEmpty {
                        Text("예: \"미분류 파일들은 work/으로 이동해줘\"")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $appState.organizeVM.followUpInput)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 36, maxHeight: 100)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(4)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

                VStack(spacing: 4) {
                    Button {
                        vm.sendFollowUp(claude: appState.claude, sessionStore: appState.sessionStore)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                vm.followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isRunning
                                ? Color.secondary
                                : Color.accentColor
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isRunning)
                    .keyboardShortcut(.return, modifiers: .command)

                    Text("⌘↩")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func followUpEntry(_ entry: OrganizeViewModel.FollowUpEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 사용자 지시
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(entry.instruction)
                    .font(.system(size: 12, weight: .medium))
            }

            // 결과
            if !entry.result.isEmpty {
                Markdown(entry.result)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("처리 중...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
