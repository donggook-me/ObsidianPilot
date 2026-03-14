import SwiftUI
import MarkdownUI

struct CaptureView: View {
    @EnvironmentObject var appState: AppState

    private var vm: CaptureViewModel { appState.captureVM }

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack {
                Text("Quick Capture")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)

            Divider()

            // Input Area
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("메모 내용")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $appState.captureVM.inputText)
                        .font(.body)
                        .frame(minHeight: 120, maxHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    Text("내용을 입력하면 Claude가 자동으로 카테고리를 분류하고 적절한 위치에 저장합니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack {
                    Spacer()

                    Button {
                        vm.capture(claude: appState.claude, sessionStore: appState.sessionStore)
                    } label: {
                        Label("저장", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isRunning || vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding()

            if vm.isRunning {
                ProgressPanel(
                    progress: vm.progress,
                    title: "분류 및 저장 중",
                    estimatedTime: appState.sessionStore.estimatedTimeString(for: "capture"),
                    onCancel: { vm.cancel() }
                )
                    .padding(.horizontal)
                    .padding(.bottom)
            }

            // Result
            if vm.showResult && !vm.result.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("저장 완료")
                            .font(.headline)
                        Spacer()
                        Button("닫기") {
                            appState.captureVM.showResult = false
                        }
                        .buttonStyle(.borderless)
                    }

                    ScrollView {
                        Markdown(vm.result)
                            .markdownTheme(.gitHub)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .background(Color.green.opacity(0.05))
            }

            if let error = vm.error {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding()
            }

            Spacer()

            FeatureHistorySection(feature: "capture", sessionStore: appState.sessionStore)
        }
    }
}
