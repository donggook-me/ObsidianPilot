import SwiftUI
import MarkdownUI

struct IdeaView: View {
    @EnvironmentObject var appState: AppState

    private var vm: IdeaViewModel { appState.ideaVM }

    var body: some View {
        HSplitView {
            // 왼쪽: 대화 영역
            conversationPanel
                .frame(minWidth: 400)

            // 오른쪽: 컨텍스트 사이드바
            contextSidebar
                .frame(width: 240)
        }
    }

    // MARK: - 대화 패널

    private var conversationPanel: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 12) {
                Text("지식 연결 아이디어")
                    .font(.headline)

                Spacer()

                if !vm.messages.isEmpty {
                    Button {
                        vm.clearConversation()
                    } label: {
                        Label("새 대화", systemImage: "plus.message")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            // 메시지 영역
            if vm.messages.isEmpty && !vm.isRunning {
                emptyState
            } else {
                messageList
            }

            // 진행 중 표시
            if vm.isRunning {
                ProgressPanel(
                    progress: vm.progress,
                    title: "아이디어 분석 중",
                    estimatedTime: appState.sessionStore.estimatedTimeString(for: "ideas"),
                    onCancel: { vm.cancel() }
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

            Divider()

            // 입력 영역
            inputArea
        }
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                Image(systemName: "lightbulb")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)

                Text("지식 연결 아이디어")
                    .font(.title2)

                Text("vault의 노트들을 분석하여 새로운 연결점과 아이디어를 탐색합니다.\n아래 프리셋으로 빠르게 시작하거나, 자유롭게 질문하세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // 프리셋 버튼들
                VStack(spacing: 8) {
                    Text("빠른 시작")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach([IdeaPreset.fullAnalysis, .crossCategory, .gaps, .recentConnections], id: \.label) { preset in
                            presetButton(preset)
                        }
                    }
                }
                .frame(maxWidth: 400)

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    private func presetButton(_ preset: IdeaPreset) -> some View {
        Button {
            vm.runPreset(preset, claude: appState.claude, sessionStore: appState.sessionStore)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.label)
                        .font(.system(size: 12, weight: .medium))
                    Text(preset.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(vm.isRunning)
    }

    // MARK: - 메시지 리스트

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: IdeaMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.body)
                        .padding(12)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(message.timestamp, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Text("ObsidianPilot")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Markdown(message.content)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

        case .context:
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text(message.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 입력 영역

    private var inputArea: some View {
        VStack(spacing: 8) {
            // 카테고리 필터 칩
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("참고 범위:")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    if let ctx = vm.vaultContext {
                        ForEach(ctx.categories) { cat in
                            categoryChip(cat)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // 텍스트 입력 + 전송
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if vm.userInput.isEmpty {
                        Text("어떤 아이디어를 탐색할까요? (예: \"카테고리 간 연결점을 찾아줘\")")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                    }

                    TextEditor(text: $appState.ideaVM.userInput)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 40, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2))
                )

                Button {
                    vm.sendMessage(
                        claude: appState.claude,
                        vault: appState.vault,
                        sessionStore: appState.sessionStore
                    )
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isRunning
                            ? Color.secondary
                            : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(vm.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isRunning)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .padding(.top, 8)
    }

    private func categoryChip(_ cat: VaultCategoryInfo) -> some View {
        let isSelected = vm.selectedCategories.contains(cat.name)
        return Button {
            if isSelected {
                appState.ideaVM.selectedCategories.remove(cat.name)
            } else {
                appState.ideaVM.selectedCategories.insert(cat.name)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: cat.icon)
                    .font(.system(size: 10))
                Text(cat.name.capitalized)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 컨텍스트 사이드바

    private var contextSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vault 컨텍스트")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    vm.loadVaultContext(vault: appState.vault)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)

            Divider()

            if vm.isLoadingContext {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let ctx = vm.vaultContext {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 카테고리별 파일 수
                        VStack(alignment: .leading, spacing: 8) {
                            Label("카테고리 (\(ctx.totalFiles) 파일)", systemImage: "folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            ForEach(ctx.categories) { cat in
                                HStack(spacing: 6) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 11))
                                        .frame(width: 14)
                                    Text(cat.name.capitalized)
                                        .font(.system(size: 12))
                                    Spacer()
                                    Text("\(cat.fileCount)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Divider()

                        // 최근 수정 파일
                        VStack(alignment: .leading, spacing: 8) {
                            Label("최근 수정", systemImage: "clock")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            ForEach(ctx.recentFiles.prefix(8)) { file in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Image(systemName: VaultCategoryInfo.iconFor(file.category))
                                            .font(.system(size: 9))
                                        Text(file.timeAgo)
                                            .font(.system(size: 10))
                                    }
                                    .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("컨텍스트를 로드하면\nvault 구조를 확인할 수 있습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button("컨텍스트 로드") {
                        vm.loadVaultContext(vault: appState.vault)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .padding()
            }

            Divider()

            // 히스토리 링크
            FeatureHistorySection(
                feature: "ideas",
                sessionStore: appState.sessionStore
            )
        }
    }
}
