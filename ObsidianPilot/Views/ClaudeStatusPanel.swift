import SwiftUI

struct ClaudeStatusPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var uptimeRefresh = false

    private var usage: ClaudeUsageStats { appState.claudeUsage }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // 메인 상태 행 (클릭으로 확장/축소)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if isExpanded {
                    appState.claudeUsage.loadStatsCache(claudePath: appState.claude.claudePath)
                }
            } label: {
                HStack(spacing: 6) {
                    statusIndicator
                    statusText
                    Spacer()

                    // 세션 비용 뱃지
                    if usage.sessionCostUSD > 0 {
                        Text(usage.sessionCostString)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(costColor.opacity(0.12))
                            .foregroundStyle(costColor)
                            .clipShape(Capsule())
                    }

                    if usage.activeTaskCount > 0 {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 확장 패널
            if isExpanded {
                expandedPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in uptimeRefresh.toggle() }
            }
        }
    }

    private var costColor: Color {
        if usage.sessionCostUSD > 5.0 { return .red }
        if usage.sessionCostUSD > 1.0 { return .orange }
        return .green
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        if appState.isWarmingUp {
            ProgressView()
                .controlSize(.mini)
        } else if appState.isClaudeReady {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
        } else {
            Circle()
                .fill(.orange)
                .frame(width: 7, height: 7)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if appState.isWarmingUp {
            Text("연결 중...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if appState.isClaudeReady {
            Text("Claude 연결됨")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            Text("독립 모드")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 요금제 & 모델
            planSection

            Divider().padding(.vertical, 2)

            // 이번 세션 사용량
            sessionUsageSection

            if usage.totalTasks > 0 {
                Divider().padding(.vertical, 2)

                // 누적 통계
                cumulativeStats
            }

            Divider().padding(.vertical, 2)

            // 오늘 기록
            todaySummary

            // 업타임
            let _ = uptimeRefresh
            infoRow(icon: "clock", label: "앱 가동", value: usage.uptimeString)

            Divider().padding(.vertical, 2)

            // Doctor 진단 버튼
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.activeToolTab = .doctor
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 11))
                    Text("Doctor 진단")
                        .font(.system(size: 11))
                    Spacer()
                    Text("⇧⌘D")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Plan Section

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("요금제")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(usage.planTier)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            if !usage.currentModel.isEmpty {
                infoRow(icon: "cpu", label: "모델", value: usage.currentModel)
            }

            if usage.contextWindow > 0 {
                infoRow(icon: "text.alignleft", label: "컨텍스트", value: "\(usage.contextWindow / 1000)K")
            }
        }
    }

    // MARK: - Session Usage

    private var sessionUsageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("이번 세션", systemImage: "gauge.with.needle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            // 비용
            HStack {
                Text("비용")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(usage.sessionCostString)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(costColor)
            }

            // 토큰 사용량 바
            if usage.sessionInputTokens + usage.sessionOutputTokens > 0 {
                tokenBar
            }

            // 토큰 상세
            HStack(spacing: 12) {
                tokenStat(label: "입력", value: usage.formatTokens(usage.sessionInputTokens), color: .blue)
                tokenStat(label: "출력", value: usage.formatTokens(usage.sessionOutputTokens), color: .purple)
                tokenStat(label: "캐시", value: usage.formatTokens(usage.sessionCacheTokens), color: .gray)
            }
        }
    }

    private var tokenBar: some View {
        let total = max(usage.sessionInputTokens + usage.sessionOutputTokens, 1)
        let inputRatio = CGFloat(usage.sessionInputTokens) / CGFloat(total)

        return GeometryReader { geo in
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: geo.size.width * inputRatio)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.purple.opacity(0.6))
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func tokenStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Cumulative Stats

    private var cumulativeStats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("누적 통계", systemImage: "chart.bar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                statCell(value: "\(usage.totalTasks)", label: "작업 수", color: .blue)
                statCell(value: "\(usage.totalToolCalls)", label: "도구 호출", color: .purple)
                statCell(value: "\(usage.totalFilesProcessed)", label: "파일 처리", color: .teal)
                statCell(value: usage.totalTimeString, label: "소요 시간", color: .orange)
            }
        }
    }

    private func statCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todaySummary: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todaySessions = appState.sessionStore.sessions.filter { $0.timestamp >= today }
        let successCount = todaySessions.filter { $0.isSuccess }.count
        let failCount = todaySessions.filter { !$0.isSuccess }.count

        return VStack(alignment: .leading, spacing: 4) {
            Label("오늘 기록", systemImage: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("\(successCount)")
                        .font(.system(size: 11, design: .monospaced))
                }
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text("\(failCount)")
                        .font(.system(size: 11, design: .monospaced))
                }
                Spacer()
                Text("총 \(todaySessions.count)건")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
