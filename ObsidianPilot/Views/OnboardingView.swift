import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    @State private var currentStep = 0
    @State private var vaultPath = ""
    @State private var claudePath = ""
    @State private var isTestingClaude = false
    @State private var claudeTestResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 40))
                    .foregroundStyle(.purple)
                Text("ObsidianPilot")
                    .font(.largeTitle.bold())
                Text("Claude AI로 Obsidian Vault를 스마트하게 관리하세요")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("메모 캡처 · 자동 분류 · 내용 검증 · 아이디어 발견")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            // 스텝 인디케이터
            HStack(spacing: 24) {
                stepIndicator(0, label: "Vault 선택")
                stepConnector(completed: currentStep > 0)
                stepIndicator(1, label: "Claude CLI")
                stepConnector(completed: currentStep > 1)
                stepIndicator(2, label: "완료")
            }
            .padding(.bottom, 32)

            Divider()

            // 스텝 콘텐츠 (스크롤 가능, 남은 공간 채움)
            ScrollView {
                Group {
                    switch currentStep {
                    case 0: vaultStep
                    case 1: claudeStep
                    case 2: completeStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(32)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // 하단 버튼 (항상 고정)
            HStack {
                if currentStep > 0 {
                    Button("이전") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                nextButton
            }
            .padding(20)
            .background(.bar)
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            // 자동 감지 시도
            claudePath = SettingsService.detectClaudePath()
        }
    }

    // MARK: - Step 1: Vault 선택

    private var vaultStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Obsidian Vault 폴더를 선택하세요")
                .font(.title3.bold())

            Text("ObsidianPilot이 분석하고 정리할 Obsidian vault의 경로입니다.\n.obsidian 폴더가 있는 디렉토리를 선택해주세요.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    if vaultPath.isEmpty {
                        Text("/Users/me/Documents/MyVault")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    }
                    TextField("", text: $vaultPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Button("찾아보기") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Obsidian vault 폴더를 선택하세요"
                    if panel.runModal() == .OK, let url = panel.url {
                        vaultPath = url.path
                    }
                }
                .buttonStyle(.bordered)
            }

            // 검증 상태
            if !vaultPath.isEmpty {
                let isValid = SettingsService.isValidVault(vaultPath)
                HStack(spacing: 6) {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isValid ? .green : .orange)
                    Text(isValid ? "유효한 Obsidian vault입니다" : ".obsidian 폴더를 찾을 수 없습니다 (마크다운 파일이 있으면 사용 가능)")
                        .font(.callout)
                        .foregroundStyle(isValid ? .green : .orange)
                }
            }

            Spacer()
        }
    }

    // MARK: - Step 2: Claude CLI

    private var claudeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Claude CLI 설정")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("ObsidianPilot은 Claude CLI를 통해 AI 기능을 제공합니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Link("Claude CLI 설치 방법 →",
                     destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!)
                    .font(.callout)
            }

            HStack(spacing: 12) {
                TextField("Claude CLI 경로", text: $claudePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("찾아보기") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowsMultipleSelection = false
                    panel.message = "claude 실행 파일을 선택하세요"
                    if panel.runModal() == .OK, let url = panel.url {
                        claudePath = url.path
                    }
                }
                .buttonStyle(.bordered)
            }

            // 검증 + 테스트
            HStack(spacing: 12) {
                if SettingsService.isValidClaude(claudePath) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("실행 파일 확인됨")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }

                    Button {
                        testClaude()
                    } label: {
                        if isTestingClaude {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("연결 테스트", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingClaude)
                } else if !claudePath.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("실행 파일을 찾을 수 없습니다")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let result = claudeTestResult {
                switch result {
                case .success(let msg):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure(let msg):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()
        }
    }

    // MARK: - Step 3: 완료

    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("설정 완료!")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                settingSummaryRow(icon: "folder.fill", label: "Vault", value: vaultPath)
                settingSummaryRow(icon: "terminal.fill", label: "Claude CLI", value: claudePath)
            }
            .padding(20)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("설정은 나중에 Settings(⌘,)에서 변경할 수 있습니다")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private func settingSummaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - 하단 버튼

    @ViewBuilder
    private var nextButton: some View {
        switch currentStep {
        case 0:
            Button("다음") {
                withAnimation { currentStep = 1 }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vaultPath.isEmpty)

        case 1:
            Button("다음") {
                withAnimation { currentStep = 2 }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!SettingsService.isValidClaude(claudePath))

        case 2:
            Button("시작하기") {
                appState.completeOnboarding(vaultPath: vaultPath, claudePath: claudePath)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        default:
            EmptyView()
        }
    }

    // MARK: - 스텝 인디케이터

    private func stepIndicator(_ step: Int, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(currentStep >= step ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 28)
                if currentStep > step {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(currentStep >= step ? .white : .secondary)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(currentStep >= step ? .primary : .tertiary)
        }
    }

    private func stepConnector(completed: Bool) -> some View {
        Rectangle()
            .fill(completed ? Color.accentColor : Color.secondary.opacity(0.2))
            .frame(width: 40, height: 2)
            .offset(y: -10)
    }

    // MARK: - Claude 테스트

    private func testClaude() {
        isTestingClaude = true
        claudeTestResult = nil

        Task {
            let result = await runClaudeTest()
            await MainActor.run {
                claudeTestResult = result
                isTestingClaude = false
            }
        }
    }

    private func runClaudeTest() async -> TestResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", "--output-format", "text", "Say hello in one word"]

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure("실행 실패: \(error.localizedDescription)")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: .success("Claude 연결 성공: \(output)"))
                } else {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "알 수 없는 오류"
                    continuation.resume(returning: .failure("Claude CLI 오류: \(errMsg)"))
                }
            }
        }
    }
}
