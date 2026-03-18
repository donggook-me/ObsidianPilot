import SwiftUI

struct VerifyView: View {
    @EnvironmentObject var appState: AppState

    private var vm: VerifyViewModel { appState.verifyVM }

    var body: some View {
        HStack(spacing: 0) {
            // Left: File List + 기록
            VStack(spacing: 0) {
                HStack {
                    Text("최근 파일")
                        .font(.headline)
                    Spacer()
                    Button {
                        vm.loadRecentFiles(vault: appState.vault)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(.bar)

                Divider()

                List(vm.recentFiles, selection: $appState.verifyVM.selectedFile) { file in
                    HStack {
                        Image(systemName: VaultCategoryInfo.iconFor(file.category))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(file.relativePath)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(file.timeAgo)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(file)
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)

                FeatureHistorySection(feature: "verify", sessionStore: appState.sessionStore)
            }
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)

            Divider()

            // Right: Verify Result
            VStack(spacing: 0) {
                if let file = vm.selectedFile {
                    HStack {
                        Image(systemName: VaultCategoryInfo.iconFor(file.category))
                        Text(file.displayName)
                            .font(.headline)
                        Spacer()

                        Button {
                            vm.verify(claude: appState.claude, sessionStore: appState.sessionStore)
                        } label: {
                            Label("검증", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRunning)
                    }
                    .padding(12)
                    .background(.bar)

                    Divider()
                }

                if vm.isRunning {
                    ProgressPanel(
                        progress: vm.progress,
                        title: "내용 검증 중",
                        estimatedTime: appState.sessionStore.estimatedTimeString(for: "verify"),
                        onCancel: { vm.cancel() }
                    )
                        .padding()
                    Spacer()
                } else if let error = vm.error {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else if vm.result.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("좌측에서 검증할 파일을 선택하세요.\n\nClaude가 노트 내용의 정확성, 논리적 일관성,\n누락된 정보를 검토하여 피드백을 제공합니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    MathMarkdownView(content: vm.result)
                }
            }
            .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity)
        }
        .onAppear {
            if vm.recentFiles.isEmpty {
                vm.loadRecentFiles(vault: appState.vault)
            }
        }
    }
}
