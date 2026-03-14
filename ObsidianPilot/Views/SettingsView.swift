import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingVaultPath: String = ""
    @State private var editingClaudePath: String = ""

    var body: some View {
        Form {
            Section("Vault 설정") {
                HStack {
                    TextField("Vault 경로", text: $editingVaultPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("찾아보기") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            editingVaultPath = url.path
                        }
                    }
                }

                if editingVaultPath != appState.settings.vaultPath {
                    Button("Vault 경로 저장") {
                        appState.updateVaultPath(editingVaultPath)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Section("Claude CLI") {
                HStack {
                    TextField("Claude CLI 경로", text: $editingClaudePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("찾아보기") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            editingClaudePath = url.path
                        }
                    }
                }

                HStack(spacing: 8) {
                    if editingClaudePath != appState.settings.claudePath {
                        Button("Claude 경로 저장") {
                            appState.updateClaudePath(editingClaudePath)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if SettingsService.isValidClaude(editingClaudePath) {
                        Label("실행 파일 확인됨", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if !editingClaudePath.isEmpty {
                        Label("실행 파일을 찾을 수 없습니다", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("초기화") {
                Button("온보딩 다시 실행") {
                    appState.settings.isOnboarded = false
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520, height: 350)
        .onAppear {
            editingVaultPath = appState.settings.vaultPath
            editingClaudePath = appState.settings.claudePath
        }
    }
}
