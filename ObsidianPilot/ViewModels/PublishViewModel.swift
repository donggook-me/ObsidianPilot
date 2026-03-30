import Foundation
import SwiftUI

/// blog/ 폴더의 마크다운 파일 상태
struct BlogPost: Identifiable, Hashable {
    let id = UUID()
    let file: VaultFile
    var frontmatter: BlogFrontmatter?
    var isSelected: Bool = false

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: BlogPost, rhs: BlogPost) -> Bool {
        lhs.id == rhs.id
    }
}

struct BlogFrontmatter {
    var title: String = ""
    var date: String = ""
    var draft: Bool = true
    var description: String = ""
}

enum PublishPhase: String {
    case idle = "대기"
    case polishing = "맞춤법 교정 중"
    case deploying = "배포 중"
    case done = "완료"
    case failed = "실패"
}

/// 다듬기 결과
struct PolishResult {
    let original: String
    let polished: String
    let report: String        // Claude가 보고한 수정 내역
}

@MainActor
class PublishViewModel: ObservableObject {
    @Published var blogPosts: [BlogPost] = []
    @Published var selectedPost: BlogPost?
    @Published var isRunning = false
    @Published var error: String?
    @Published var result: String = ""
    @Published var deployedURL: String = ""
    @Published var currentPhase: PublishPhase = .idle
    @Published var polishResult: PolishResult?
    @Published var postContent: String = ""     // 선택된 글 원문
    @Published var isPolished: Bool = false      // 다듬기 완료 여부
    @Published var lastRefreshed: Date? = nil    // 마지막 새로고침 시각
    let progress = StreamProgress()

    /// 자동 갱신 타이머 (5분 간격)
    private var autoRefreshTimer: Timer?
    private weak var vaultRef: VaultService?

    /// blog/ 폴더에서 마크다운 파일 목록 로드
    func loadBlogPosts(vault: VaultService) {
        vaultRef = vault
        let allFiles = vault.allMarkdownFiles()
        let previousSelection = selectedPost?.file.relativePath
        blogPosts = allFiles
            .filter { $0.category.lowercased() == "blog" }
            .sorted { $0.modifiedDate > $1.modifiedDate }
            .map { file in
                var post = BlogPost(file: file)
                post.frontmatter = parseFrontmatter(at: file.fullPath)
                return post
            }
        lastRefreshed = Date()

        // 기존 선택 유지
        if let prevPath = previousSelection {
            selectedPost = blogPosts.first(where: { $0.file.relativePath == prevPath })
        }
    }

    /// 자동 갱신 시작 (5분 간격)
    func startAutoRefresh(vault: VaultService) {
        vaultRef = vault
        stopAutoRefresh()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let vault = self.vaultRef, !self.isRunning else { return }
                self.loadBlogPosts(vault: vault)
            }
        }
    }

    /// 자동 갱신 정지
    func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    deinit {
        autoRefreshTimer?.invalidate()
    }

    /// 글 선택 시 원문 로드
    func selectPost(_ post: BlogPost) {
        selectedPost = post
        polishResult = nil
        isPolished = false
        error = nil
        result = ""
        deployedURL = ""
        currentPhase = .idle
        loadContent(for: post)
    }

    private func loadContent(for post: BlogPost) {
        if let content = try? String(contentsOfFile: post.file.fullPath, encoding: .utf8) {
            postContent = content
        } else {
            postContent = "(파일을 읽을 수 없습니다)"
        }
    }

    /// frontmatter 간이 파싱
    private func parseFrontmatter(at path: String) -> BlogFrontmatter? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        guard content.hasPrefix("---") else { return nil }

        let lines = content.components(separatedBy: "\n")
        var fm = BlogFrontmatter()
        var inFrontmatter = false

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if inFrontmatter { break }
                inFrontmatter = true
                continue
            }
            if inFrontmatter {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                switch key {
                case "title": fm.title = value
                case "date": fm.date = value
                case "draft": fm.draft = value.lowercased() == "true"
                case "description": fm.description = value
                default: break
                }
            }
        }

        return fm
    }

    // MARK: - 다듬기 (맞춤법 교정만)

    func polish(claude: ClaudeService, sessionStore: SessionStore) {
        guard let post = selectedPost, !isRunning else { return }
        isRunning = true
        error = nil
        result = ""
        currentPhase = .polishing
        polishResult = nil

        let filePath = post.file.relativePath
        let fileName = post.file.displayName
        let originalContent = postContent

        Task {
            do {
                let report = try await claude.publishPolish(
                    filePath: filePath,
                    progress: progress
                )

                if progress.isCancelled { return }

                // 수정 후 파일 다시 읽기
                let polished = (try? String(contentsOfFile: post.file.fullPath, encoding: .utf8)) ?? originalContent

                polishResult = PolishResult(
                    original: originalContent,
                    polished: polished,
                    report: report
                )
                postContent = polished
                isPolished = true
                currentPhase = .idle

                // frontmatter 갱신
                if let idx = blogPosts.firstIndex(where: { $0.id == post.id }) {
                    blogPosts[idx].frontmatter = parseFrontmatter(at: post.file.fullPath)
                    selectedPost = blogPosts[idx]
                }

                sessionStore.add(Session(
                    feature: "publish",
                    input: "다듬기: \(fileName)",
                    result: report,
                    durationSeconds: progress.elapsedSeconds
                ))

            } catch is CancellationError {
                // cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                currentPhase = .failed
                self.error = error.localizedDescription
            }
            self.isRunning = false
        }
    }

    // MARK: - 배포

    func deploy(claude: ClaudeService, sessionStore: SessionStore) {
        guard let post = selectedPost, !isRunning else { return }
        isRunning = true
        error = nil
        result = ""
        deployedURL = ""
        currentPhase = .deploying

        let filePath = post.file.relativePath
        let fileName = post.file.displayName

        Task {
            do {
                let deployResult = try await claude.publishDeploy(
                    filePath: filePath,
                    progress: progress
                )

                if progress.isCancelled { return }

                currentPhase = .done

                if let url = extractURL(from: deployResult) {
                    deployedURL = url
                }

                self.result = deployResult

                // frontmatter 갱신 (draft → false 반영)
                if let idx = blogPosts.firstIndex(where: { $0.id == post.id }) {
                    blogPosts[idx].frontmatter = parseFrontmatter(at: post.file.fullPath)
                    selectedPost = blogPosts[idx]
                }

                sessionStore.add(Session(
                    feature: "publish",
                    input: "배포: \(fileName)",
                    result: self.result,
                    durationSeconds: progress.elapsedSeconds
                ))

            } catch is CancellationError {
                // cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                currentPhase = .failed
                self.error = error.localizedDescription
                sessionStore.add(Session(
                    feature: "publish",
                    input: "배포: \(fileName)",
                    result: error.localizedDescription,
                    isSuccess: false,
                    durationSeconds: progress.elapsedSeconds
                ))
            }
            self.isRunning = false
        }
    }

    func cancel() {
        progress.cancel()
        isRunning = false
        currentPhase = .idle
    }

    private func extractURL(from text: String) -> String? {
        let pattern = #"https?://[^\s\)\]\"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let urls = matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } }

        // .vercel.app 프로덕션 URL 우선
        if let prod = urls.first(where: { $0.contains(".vercel.app") && !$0.contains("-") }) {
            return prod
        }
        // 그 외 vercel URL
        if let vercel = urls.first(where: { $0.contains("vercel") }) {
            return vercel
        }
        return urls.first
    }
}
