import SwiftUI
import MarkdownUI

struct PublishView: View {
    @EnvironmentObject var appState: AppState

    private var vm: PublishViewModel { appState.publishVM }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Blog 파일 목록
            leftPanel

            Divider()

            // Right: 미리보기 + 액션
            rightPanel
        }
        .onAppear {
            vm.loadBlogPosts(vault: appState.vault)
            vm.startAutoRefresh(vault: appState.vault)
        }
        .onDisappear {
            vm.stopAutoRefresh()
        }
    }

    // MARK: - Left Panel (글 목록)

    private var leftPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("blog/ 글 목록")
                    .font(.headline)

                if let last = vm.lastRefreshed {
                    Text(last, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }

                Spacer()

                Text("\(vm.blogPosts.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())

                Button {
                    vm.loadBlogPosts(vault: appState.vault)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("새로고침 (5분마다 자동 갱신)")
            }
            .padding(12)
            .background(.bar)

            // 동기화 요약 바
            if !vm.blogPosts.isEmpty {
                HStack(spacing: 10) {
                    syncSummaryPill(icon: "checkmark.circle.fill", count: vm.syncSummary.synced, color: .green, label: "동기화")
                    syncSummaryPill(icon: "exclamationmark.arrow.circlepath", count: vm.syncSummary.modified, color: .blue, label: "수정됨")
                    syncSummaryPill(icon: "arrow.up.circle", count: vm.syncSummary.notDeployed, color: .orange, label: "미배포")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }

            Divider()

            if vm.blogPosts.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("blog/ 폴더에 글이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(vm.blogPosts, selection: Binding(
                    get: { vm.selectedPost },
                    set: { post in
                        if let post = post {
                            vm.selectPost(post)
                        }
                    }
                )) { post in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(post.frontmatter?.title.isEmpty == false
                                 ? post.frontmatter!.title
                                 : post.file.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                publishStatusBadge(for: post)

                                if let fm = post.frontmatter, !fm.date.isEmpty {
                                    Text(fm.date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .tag(post)
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            FeatureHistorySection(feature: "publish", sessionStore: appState.sessionStore)
        }
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 320)
    }

    @ViewBuilder
    private func publishStatusBadge(for post: BlogPost) -> some View {
        HStack(spacing: 4) {
            // draft 상태
            if let fm = post.frontmatter {
                if fm.draft {
                    Label("초안", systemImage: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                } else {
                    Label("공개", systemImage: "globe")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                }
            } else {
                Label("frontmatter 없음", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            }

            // 동기화 상태
            Text("·")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)

            Label(post.syncStatus.rawValue, systemImage: post.syncStatus.icon)
                .font(.system(size: 9))
                .foregroundStyle(syncColor(post.syncStatus))
        }
    }

    private func syncColor(_ status: SyncStatus) -> Color {
        switch status {
        case .synced: return .green
        case .modified: return .blue
        case .notDeployed: return .orange
        case .deployOnly: return .red
        }
    }

    // MARK: - Right Panel (미리보기 + 액션)

    private var rightPanel: some View {
        VStack(spacing: 0) {
            if let post = vm.selectedPost {
                // 상단 액션 바
                actionBar(post: post)

                Divider()

                // 콘텐츠 영역
                contentArea
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("좌측에서 글을 선택하세요")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .frame(minWidth: 300, idealWidth: 450, maxWidth: .infinity)
    }

    // MARK: - Action Bar

    private func actionBar(post: BlogPost) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.frontmatter?.title.isEmpty == false
                     ? post.frontmatter!.title
                     : post.file.displayName)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    publishStatusBadge(for: post)
                    if let fm = post.frontmatter, !fm.date.isEmpty {
                        Text(fm.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if vm.isRunning {
                phaseBadge
            }

            // 다듬기 버튼
            Button {
                vm.polish(claude: appState.claude, sessionStore: appState.sessionStore)
            } label: {
                Label("다듬기", systemImage: "wand.and.stars")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .disabled(vm.isRunning)
            .help("맞춤법·띄어쓰기 교정 (내용 변경 없음)")

            // 배포 버튼
            Button {
                vm.deploy(claude: appState.claude, sessionStore: appState.sessionStore)
            } label: {
                Label("배포", systemImage: "paperplane.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(vm.isRunning)
            .help("Astro 블로그에 빌드 & 배포")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var phaseBadge: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.mini)
            Text(vm.currentPhase.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if vm.isRunning {
            // 작업 중: ProgressPanel 재활용
            ProgressPanel(
                progress: vm.progress,
                title: vm.currentPhase.rawValue,
                estimatedTime: appState.sessionStore.estimatedTimeString(for: "publish"),
                onCancel: { vm.cancel() }
            )
            .padding()
            Spacer()

        } else if let error = vm.error {
            // 에러
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()

        } else if vm.showDeployResult && !vm.result.isEmpty {
            // 배포 완료
            deploySuccessView

        } else if let pr = vm.polishResult {
            // 다듬기 결과 표시
            polishResultView(pr)

        } else {
            // 기본: 글 미리보기
            postPreview
        }
    }

    // MARK: - Post Preview (글 미리보기)

    private var postPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // frontmatter 제거한 본문만 렌더링
                let body = stripFrontmatter(vm.postContent)

                if vm.isPolished {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("다듬기 완료")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                        Spacer()
                        Button {
                            vm.polishResult = vm.polishResult // 다시 diff 보기
                        } label: {
                            Text("수정 내역 보기")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }

                Markdown(body)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(20)
            }
        }
    }

    // MARK: - Polish Result (다듬기 결과 diff)

    private func polishResultView(_ pr: PolishResult) -> some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
                Text("다듬기 결과")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    // diff 닫고 미리보기로
                    vm.polishResult = nil
                } label: {
                    Text("미리보기로 돌아가기")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.purple.opacity(0.06))

            Divider()

            // Claude 보고서
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 수정 보고서
                    VStack(alignment: .leading, spacing: 8) {
                        Label("수정 내역", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))

                        Markdown(pr.report)
                            .markdownTheme(.gitHub)
                            .textSelection(.enabled)
                    }

                    Divider()

                    // 변경 전/후 비교 (변경된 부분만)
                    let diffs = computeLineDiffs(original: pr.original, polished: pr.polished)
                    if diffs.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.green)
                            Text("텍스트 변경 없음 (frontmatter만 수정됨)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("변경 비교 (\(diffs.count)건)", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 13, weight: .semibold))

                            ForEach(Array(diffs.enumerated()), id: \.offset) { _, diff in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.red)
                                        Text(diff.original)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.red.opacity(0.8))
                                            .strikethrough()
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.green)
                                        Text(diff.polished)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.green.opacity(0.9))
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Deploy Success

    private var deploySuccessView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("배포 완료")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if !vm.deployedURL.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(vm.deployedURL, forType: .string)
                    } label: {
                        Label("URL 복사", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let url = URL(string: vm.deployedURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("열기", systemImage: "safari")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.06))

            // 배포 URL 강조 표시
            if !vm.deployedURL.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(.indigo)
                    Text(vm.deployedURL)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.indigo)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.indigo.opacity(0.06))
            }

            Divider()

            // 배포 결과 상세
            ScrollView {
                Markdown(vm.result)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(16)
            }
        }
    }

    // MARK: - Helpers

    private func stripFrontmatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let lines = content.components(separatedBy: "\n")
        var endIdx = 0
        var foundFirst = false
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if foundFirst {
                    endIdx = i + 1
                    break
                }
                foundFirst = true
            }
        }
        if endIdx > 0 {
            return lines[endIdx...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content
    }

    struct LineDiff {
        let original: String
        let polished: String
    }

    private func syncSummaryPill(icon: String, count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func computeLineDiffs(original: String, polished: String) -> [LineDiff] {
        let origLines = original.components(separatedBy: "\n")
        let polLines = polished.components(separatedBy: "\n")
        var diffs: [LineDiff] = []

        let maxCount = max(origLines.count, polLines.count)
        for i in 0..<maxCount {
            let o = i < origLines.count ? origLines[i] : ""
            let p = i < polLines.count ? polLines[i] : ""
            if o != p && !(o.trimmingCharacters(in: .whitespaces).isEmpty && p.trimmingCharacters(in: .whitespaces).isEmpty) {
                // frontmatter 구분자(---)만 다른 경우 스킵
                if o.trimmingCharacters(in: .whitespaces) == "---" && p.trimmingCharacters(in: .whitespaces) == "---" { continue }
                diffs.append(LineDiff(original: o, polished: p))
            }
        }

        return diffs
    }
}
