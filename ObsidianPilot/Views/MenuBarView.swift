import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var organizeExpanded = false
    @State private var ideasExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("ObsidianPilot")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // ── Organize (카테고리 선택 + 실행 분리) ──
            MenuBarExpandableRow(
                icon: "folder.badge.gearshape",
                title: "Organize",
                subtitle: appState.organizeVM.isRunning
                    ? appState.organizeVM.progress.currentActivity
                    : organizeCategoryLabel,
                selectedBadge: organizeExpanded ? nil : organizeCategoryLabel,
                isRunning: appState.organizeVM.isRunning,
                isExpanded: $organizeExpanded,
                onRun: {
                    appState.organizeVM.run(claude: appState.claude, sessionStore: appState.sessionStore)
                    organizeExpanded = false
                },
                onOpen: { openMainWindow(tab: .organize) }
            ) {
                ForEach(appState.organizeVM.categories, id: \.0) { cat in
                    SubMenuButton(
                        icon: cat.2,
                        label: cat.1,
                        isSelected: appState.organizeVM.selectedCategory == cat.0
                    ) {
                        appState.organizeVM.selectedCategory = cat.0
                    }
                }
            }

            // ── Ideas (분석 범위 선택 + 실행 분리) ──
            MenuBarExpandableRow(
                icon: "lightbulb",
                title: "Ideas",
                subtitle: appState.ideaVM.isRunning
                    ? appState.ideaVM.progress.currentActivity
                    : ideaFocusLabel,
                selectedBadge: ideasExpanded ? nil : ideaFocusLabel,
                isRunning: appState.ideaVM.isRunning,
                isExpanded: $ideasExpanded,
                onRun: {
                    let focus = appState.ideaVM.selectedFocus
                    if focus == "all" {
                        appState.ideaVM.suggest(claude: appState.claude, sessionStore: appState.sessionStore)
                    } else {
                        appState.ideaVM.suggestFocused(
                            focus: focus,
                            claude: appState.claude,
                            sessionStore: appState.sessionStore
                        )
                    }
                    ideasExpanded = false
                },
                onOpen: { openMainWindow(tab: .ideas) }
            ) {
                let ideaOptions: [(String, String, String)] = [
                    ("all", "전체 분석", "sparkles"),
                    ("cross", "카테고리 간 연결", "link"),
                    ("gaps", "학습 갭 분석", "magnifyingglass"),
                    ("recent", "최근 노트 연결", "clock.arrow.2.circlepath"),
                ]

                ForEach(ideaOptions, id: \.0) { opt in
                    SubMenuButton(
                        icon: opt.2,
                        label: opt.1,
                        isSelected: appState.ideaVM.selectedFocus == opt.0
                    ) {
                        appState.ideaVM.selectedFocus = opt.0
                    }
                }
            }

            // ── Verify ──
            MenuBarSimpleRow(
                icon: "checkmark.shield",
                title: "Verify",
                subtitle: appState.verifyVM.isRunning
                    ? appState.verifyVM.progress.currentActivity
                    : "파일 선택 후 검증",
                isRunning: appState.verifyVM.isRunning,
                action: { openMainWindow(tab: .verify) }
            )

            // ── Capture ──
            MenuBarSimpleRow(
                icon: "square.and.pencil",
                title: "Capture",
                subtitle: appState.captureVM.isRunning
                    ? appState.captureVM.progress.currentActivity
                    : "빠른 메모 작성",
                isRunning: appState.captureVM.isRunning,
                action: { openMainWindow(tab: .capture) }
            )

            Divider()

            // 진행 중인 작업 요약
            let running = appState.runningTabs
            if !running.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(running) { tab in
                        RunningStatusRow(tab: tab, appState: appState)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Divider()
            }

            // 하단
            HStack(spacing: 8) {
                Button {
                    openMainWindow(tab: appState.selectedTab)
                } label: {
                    Label("윈도우 열기", systemImage: "macwindow")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    openMainWindow(tab: .history)
                } label: {
                    Label("\(appState.sessionStore.sessions.count)", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            Divider()

            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(width: 290)
    }

    private var organizeCategoryLabel: String {
        // 동적 카테고리에서 label 찾기
        if let found = appState.organizeVM.categories.first(where: { $0.0 == appState.organizeVM.selectedCategory }) {
            return found.1
        }
        return "카테고리 선택"
    }

    private var ideaFocusLabel: String {
        let map: [String: String] = [
            "all": "전체 분석",
            "cross": "카테고리 간 연결",
            "gaps": "학습 갭 분석",
            "recent": "최근 노트 연결",
        ]
        return map[appState.ideaVM.selectedFocus] ?? "전체 분석"
    }

    private func openMainWindow(tab: AppTab) {
        appState.selectedTab = tab
        AppDelegate.showMainWindow()
    }
}

// MARK: - 확장 가능한 행 (서브메뉴 + 실행 버튼 분리)

struct MenuBarExpandableRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var selectedBadge: String? = nil
    let isRunning: Bool
    @Binding var isExpanded: Bool
    var onRun: (() -> Void)? = nil
    let onOpen: () -> Void
    @ViewBuilder let submenu: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // 메인 영역: 토글 확장
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: icon)
                                .frame(width: 18)
                                .foregroundStyle(isRunning ? .blue : .primary)
                            if isRunning {
                                ProgressView()
                                    .controlSize(.mini)
                                    .offset(x: 10, y: -6)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(title)
                                    .font(.system(size: 13, weight: .medium))
                                if let badge = selectedBadge {
                                    Text(badge)
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                // 실행 버튼 (선택된 카테고리로 바로 실행)
                if let onRun = onRun {
                    Button(action: onRun) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(isRunning ? Color.gray : Color.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning)
                    .help("선택된 항목으로 실행")
                }

                // 윈도우 열기
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("상세 결과 보기")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())

            // 서브메뉴
            if isExpanded && !isRunning {
                VStack(alignment: .leading, spacing: 0) {
                    submenu
                }
                .padding(.leading, 30)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 단순 행 (서브메뉴 없음)

struct MenuBarSimpleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: icon)
                        .frame(width: 18)
                        .foregroundStyle(isRunning ? .blue : .primary)
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .offset(x: 10, y: -6)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

// MARK: - 서브메뉴 버튼 (선택만, 실행하지 않음)

struct SubMenuButton: View {
    let icon: String
    let label: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 14)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 진행 중인 작업 상태

struct RunningStatusRow: View {
    let tab: AppTab
    let appState: AppState

    var body: some View {
        let progress = progressFor(tab)

        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)

            Text(tab.rawValue)
                .font(.system(size: 11, weight: .medium))

            Text(progress?.formattedTime ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            if let p = progress, p.toolCallCount > 0 {
                Text("\(p.toolCallCount) steps")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // 취소 버튼
            Button {
                cancelTask(tab)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("작업 취소")
        }
    }

    private func progressFor(_ tab: AppTab) -> StreamProgress? {
        switch tab {
        case .organize: return appState.organizeVM.progress
        case .verify: return appState.verifyVM.progress
        case .ideas: return appState.ideaVM.progress
        case .publish: return appState.publishVM.progress
        case .capture: return appState.captureVM.progress
        case .history, .doctor: return nil
        }
    }

    private func cancelTask(_ tab: AppTab) {
        switch tab {
        case .organize: appState.organizeVM.cancel()
        case .verify: appState.verifyVM.cancel()
        case .ideas: appState.ideaVM.cancel()
        case .publish: appState.publishVM.cancel()
        case .capture: appState.captureVM.cancel()
        case .history, .doctor: break
        }
    }
}
