import SwiftUI
import UserNotifications
import Combine

extension Notification.Name {
    static let openMainWindow = Notification.Name("openMainWindow")
}

@main
struct ObsidianPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    init() {
        // AppDelegate에 appState 전달 (NSStatusItem 메뉴용)
        AppDelegate.sharedAppState = appState
    }

    var body: some Scene {
        WindowGroup("ObsidianPilot") {
            Group {
                if appState.settings.isOnboarded {
                    MainWindow()
                        .frame(minWidth: 700, minHeight: 500)
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .handlesExternalEvents(preferring: ["main"], allowing: ["main"])
        }
        .defaultSize(width: appState.settings.isOnboarded ? 800 : 560, height: appState.settings.isOnboarded ? 600 : 520)
        .windowResizability(.contentMinSize)
        .handlesExternalEvents(matching: ["main"])
        .commands {
            CommandMenu("이동") {
                Button("캡처 (메인)") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.activeToolTab = nil }
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("정리") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.activeToolTab = .organize }
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("검증") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.activeToolTab = .verify }
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("아이디어") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.activeToolTab = .ideas }
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("기록") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.activeToolTab = .history }
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button("Doctor 진단") {
                    withAnimation(.easeInOut(duration: 0.2)) { appState.activeToolTab = .doctor }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate (윈도우 라이프사이클 관리)

class AppDelegate: NSObject, NSApplicationDelegate {
    static var sharedAppState: AppState?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSStatusItem으로 메뉴바 아이콘 생성
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "ObsidianPilot")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 팝오버 설정
        popover = NSPopover()
        popover.contentSize = NSSize(width: 290, height: 400)
        popover.behavior = .transient
        if let appState = Self.sharedAppState {
            popover.contentViewController = NSHostingController(
                rootView: MenuBarView()
                    .environmentObject(appState)
            )
        }

        // 메인 윈도우 활성화 및 최소 크기 강제 적용
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows where !(window is NSPanel) && window.level == .normal {
                window.minSize = NSSize(width: 700, height: 500)
                // 윈도우가 최소 크기보다 작으면 복원
                if window.frame.width < 700 || window.frame.height < 500 {
                    let newWidth = max(window.frame.width, 700)
                    let newHeight = max(window.frame.height, 500)
                    window.setFrame(NSRect(
                        x: window.frame.origin.x,
                        y: window.frame.origin.y - (newHeight - window.frame.height),
                        width: newWidth, height: newHeight
                    ), display: true, animate: true)
                }
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // appState 최신 상태로 갱신
            if let appState = Self.sharedAppState {
                popover.contentViewController = NSHostingController(
                    rootView: MenuBarView()
                        .environmentObject(appState)
                )
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 팝오버에 포커스
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Self.showMainWindow()
        }
        return true
    }

    static func showMainWindow() {
        let app = NSApplication.shared

        for window in app.windows where !(window is NSPanel) && window.level == .normal {
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            return
        }

        if let url = URL(string: "obsidianpilot://main") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Claude Usage Stats

@MainActor
class ClaudeUsageStats: ObservableObject {
    // 앱 내 누적 통계
    @Published var totalTasks: Int = 0
    @Published var totalToolCalls: Int = 0
    @Published var totalFilesProcessed: Int = 0
    @Published var totalElapsedSeconds: Int = 0
    @Published var sessionStartTime: Date = Date()
    @Published var lastActivityTime: Date? = nil
    @Published var successCount: Int = 0
    @Published var failureCount: Int = 0
    @Published var activeTaskCount: Int = 0

    // 비용 & 토큰 (CLI result JSON에서 추출)
    @Published var sessionCostUSD: Double = 0
    @Published var sessionInputTokens: Int = 0
    @Published var sessionOutputTokens: Int = 0
    @Published var sessionCacheTokens: Int = 0

    // 요금제 & 모델 정보
    @Published var planTier: String = "Pro"  // CLI 기본값
    @Published var currentModel: String = ""
    @Published var contextWindow: Int = 0
    @Published var maxOutputTokens: Int = 0

    // stats-cache.json에서 읽은 전체 누적 데이터
    @Published var allTimeMessages: Int = 0
    @Published var allTimeSessions: Int = 0

    func recordTaskCompletion(toolCalls: Int, filesProcessed: Int, elapsed: Int, success: Bool) {
        totalTasks += 1
        totalToolCalls += toolCalls
        totalFilesProcessed += filesProcessed
        totalElapsedSeconds += elapsed
        lastActivityTime = Date()
        if success { successCount += 1 } else { failureCount += 1 }
    }

    /// CLI result JSON에서 사용량 정보 추출
    func recordCLIResult(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // total_cost_usd
        if let cost = json["total_cost_usd"] as? Double {
            sessionCostUSD += cost
        }

        // usage 블록
        if let usage = json["usage"] as? [String: Any] {
            sessionInputTokens += usage["input_tokens"] as? Int ?? 0
            sessionOutputTokens += usage["output_tokens"] as? Int ?? 0
            sessionCacheTokens += (usage["cache_read_input_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)

            if let tier = usage["service_tier"] as? String, !tier.isEmpty {
                planTier = tier == "standard" ? "Pro" : tier.capitalized
            }
        }

        // modelUsage — 모델명, 컨텍스트 윈도우
        if let modelUsage = json["modelUsage"] as? [String: Any] {
            for (modelKey, value) in modelUsage {
                // 모델명 정리 (e.g. "claude-opus-4-6[1m]" → "claude-opus-4-6")
                let cleanModel = modelKey.components(separatedBy: "[").first ?? modelKey
                currentModel = friendlyModelName(cleanModel)

                if let modelData = value as? [String: Any] {
                    if let cw = modelData["contextWindow"] as? Int, cw > 0 {
                        contextWindow = cw
                    }
                    if let mo = modelData["maxOutputTokens"] as? Int, mo > 0 {
                        maxOutputTokens = mo
                    }
                }
            }
        }
    }

    /// ~/.claude/stats-cache.json 에서 전체 누적 데이터 로드
    func loadStatsCache(claudePath: String) {
        Task.detached {
            let statsPath = NSHomeDirectory() + "/.claude/stats-cache.json"
            guard let data = FileManager.default.contents(atPath: statsPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let totalMessages = json["totalMessages"] as? Int ?? 0
            let totalSessions = json["totalSessions"] as? Int ?? 0

            await MainActor.run {
                self.allTimeMessages = totalMessages
                self.allTimeSessions = totalSessions
            }
        }
    }

    private func friendlyModelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus 4" }
        if model.contains("sonnet") && model.contains("4-5") { return "Sonnet 4.5" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    var sessionCostString: String {
        if sessionCostUSD < 0.01 { return "$0.00" }
        return String(format: "$%.2f", sessionCostUSD)
    }

    func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    var uptimeString: String {
        let interval = Int(Date().timeIntervalSince(sessionStartTime))
        let h = interval / 3600
        let m = (interval % 3600) / 60
        if h > 0 { return "\(h)시간 \(m)분" }
        return "\(m)분"
    }

    var totalTimeString: String {
        let m = totalElapsedSeconds / 60
        let s = totalElapsedSeconds % 60
        if m > 0 { return "\(m)분 \(s)초" }
        return "\(s)초"
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .history
    @Published var activeToolTab: AppTab? = nil
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var isClaudeReady = false
    @Published var isWarmingUp = false

    // Claude 사용량 추적
    @Published var claudeUsage = ClaudeUsageStats()

    let claude: ClaudeService
    let vault: VaultService
    let settings: SettingsService
    let sessionStore: SessionStore

    // ViewModels — AppState에서 소유하여 탭 전환 시에도 유지
    var organizeVM: OrganizeViewModel
    var verifyVM: VerifyViewModel
    var ideaVM: IdeaViewModel
    var captureVM: CaptureViewModel
    var historyVM: HistoryViewModel
    var doctorService: DoctorService

    /// 이전 실행 상태 (완료 알림 감지용)
    private var previouslyRunning: Set<String> = []
    private var notificationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.settings = SettingsService()
        self.claude = ClaudeService(vaultPath: settings.vaultPath, claudePath: settings.claudePath)
        self.vault = VaultService(vaultPath: settings.vaultPath)
        self.sessionStore = SessionStore()
        self.organizeVM = OrganizeViewModel()
        self.verifyVM = VerifyViewModel()
        self.ideaVM = IdeaViewModel()
        self.captureVM = CaptureViewModel()
        self.historyVM = HistoryViewModel()
        self.doctorService = DoctorService()

        // VM/Store 변경사항을 AppState로 전파 → View 갱신 보장
        forwardChanges(from: organizeVM)
        forwardChanges(from: verifyVM)
        forwardChanges(from: ideaVM)
        forwardChanges(from: captureVM)
        forwardChanges(from: historyVM)
        forwardChanges(from: sessionStore)
        forwardChanges(from: claudeUsage)
        forwardChanges(from: doctorService)

        // 알림 권한 요청
        requestNotificationPermission()
        // 완료 감지 타이머
        startCompletionMonitor()

        // stats-cache에서 전체 누적 데이터 로드
        claudeUsage.loadStatsCache(claudePath: claude.claudePath)

        // 백그라운드에서 Claude 세션 warm-up (vault 컨텍스트 사전 로드)
        isWarmingUp = true
        Task { [claude] in
            let success = await claude.warmUp()
            await MainActor.run {
                self.isClaudeReady = success
                self.isWarmingUp = false
            }
        }
    }

    private func forwardChanges<T: ObservableObject>(from child: T) {
        child.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func updateVaultPath(_ path: String) {
        settings.vaultPath = path
        claude.vaultPath = path
        vault.vaultPath = path
    }

    func updateClaudePath(_ path: String) {
        settings.claudePath = path
        claude.claudePath = path
    }

    func completeOnboarding(vaultPath: String, claudePath: String) {
        settings.vaultPath = vaultPath
        settings.claudePath = claudePath
        settings.isOnboarded = true
        claude.vaultPath = vaultPath
        claude.claudePath = claudePath
        vault.vaultPath = vaultPath

        // warm-up 다시 실행
        isWarmingUp = true
        Task { [claude] in
            let success = await claude.warmUp()
            await MainActor.run {
                self.isClaudeReady = success
                self.isWarmingUp = false
            }
        }
    }

    /// 현재 작업 중인 탭이 있는지
    var runningTabs: [AppTab] {
        var tabs: [AppTab] = []
        if organizeVM.isRunning { tabs.append(.organize) }
        if verifyVM.isRunning { tabs.append(.verify) }
        if ideaVM.isRunning { tabs.append(.ideas) }
        if captureVM.isRunning { tabs.append(.capture) }
        return tabs
    }

    /// 작업 중이면 애니메이션 아이콘, 아니면 기본 아이콘
    var menuBarIcon: String {
        runningTabs.isEmpty ? "brain.head.profile" : "brain.head.profile.fill"
    }

    /// 현재 실행 중인 기능 ID 집합
    private var currentlyRunningSet: Set<String> {
        var set = Set<String>()
        if organizeVM.isRunning { set.insert("organize") }
        if verifyVM.isRunning { set.insert("verify") }
        if ideaVM.isRunning { set.insert("ideas") }
        if captureVM.isRunning { set.insert("capture") }
        return set
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func startCompletionMonitor() {
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForCompletions()
            }
        }
    }

    private func checkForCompletions() {
        let current = currentlyRunningSet
        let justFinished = previouslyRunning.subtracting(current)

        // 활성 작업 수 갱신
        claudeUsage.activeTaskCount = current.count

        for feature in justFinished {
            let (success, duration) = completionInfo(for: feature)
            let progress = progressFor(feature)
            claudeUsage.recordTaskCompletion(
                toolCalls: progress?.toolCallCount ?? 0,
                filesProcessed: progress?.processedFiles.count ?? 0,
                elapsed: duration,
                success: success
            )
            // CLI result JSON에서 비용/토큰 정보 추출
            if let resultJSON = progress?.resultJSON, !resultJSON.isEmpty {
                claudeUsage.recordCLIResult(resultJSON)
            }
            sendCompletionNotification(feature: feature, success: success, duration: duration)
        }

        previouslyRunning = current
    }

    private func progressFor(_ feature: String) -> StreamProgress? {
        switch feature {
        case "organize": return organizeVM.progress
        case "verify": return verifyVM.progress
        case "ideas": return ideaVM.progress
        case "capture": return captureVM.progress
        default: return nil
        }
    }

    private func completionInfo(for feature: String) -> (success: Bool, duration: Int) {
        switch feature {
        case "organize": return (organizeVM.error == nil, organizeVM.progress.elapsedSeconds)
        case "verify": return (verifyVM.error == nil, verifyVM.progress.elapsedSeconds)
        case "ideas": return (ideaVM.error == nil, ideaVM.progress.elapsedSeconds)
        case "capture": return (captureVM.error == nil, captureVM.progress.elapsedSeconds)
        default: return (true, 0)
        }
    }

    private func sendCompletionNotification(feature: String, success: Bool, duration: Int) {
        // 앱이 포커스 상태면 알림 불필요
        if NSApplication.shared.isActive { return }

        let content = UNMutableNotificationContent()
        let label = featureLabel(feature)
        let durStr = duration > 60 ? "\(duration / 60)분 \(duration % 60)초" : "\(duration)초"

        if success {
            content.title = "\(label) 완료"
            content.body = "\(durStr) 소요. 결과를 확인하세요."
            content.sound = .default
        } else {
            content.title = "\(label) 실패"
            content.body = "오류가 발생했습니다."
            content.sound = UNNotificationSound.defaultCritical
        }

        let request = UNNotificationRequest(
            identifier: "completion-\(feature)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func featureLabel(_ feature: String) -> String {
        switch feature {
        case "organize": return "Organize"
        case "verify": return "Verify"
        case "ideas": return "Ideas"
        case "capture": return "Capture"
        default: return feature
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case organize = "Organize"
    case verify = "Verify"
    case ideas = "Ideas"
    case capture = "Capture"
    case history = "History"
    case doctor = "Doctor"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .organize: return "folder.badge.gearshape"
        case .verify: return "checkmark.shield"
        case .ideas: return "lightbulb"
        case .capture: return "square.and.pencil"
        case .history: return "clock.arrow.circlepath"
        case .doctor: return "stethoscope"
        }
    }

    var shortLabel: String {
        switch self {
        case .organize: return "정리"
        case .verify: return "검증"
        case .ideas: return "아이디어"
        case .capture: return "캡처"
        case .history: return "기록"
        case .doctor: return "Doctor"
        }
    }
}
