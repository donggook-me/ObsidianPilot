import SwiftUI
import MarkdownUI

/// Claude 작업 진행 상황을 보여주는 패널
struct ProgressPanel: View {
    @ObservedObject var progress: StreamProgress
    var title: String = "처리 중"
    var estimatedTime: String? = nil
    var onCancel: (() -> Void)? = nil

    enum Tab: String, CaseIterable {
        case steps = "진행 단계"
        case preview = "실시간 미리보기"
    }

    @State private var selectedTab: Tab = .steps

    var body: some View {
        VStack(spacing: 0) {
            // 상단: 제목 + 시간 + 통계 + 취소
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    if let est = estimatedTime {
                        Text(est)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // 통계 뱃지들
                StatBadge(icon: "clock", value: progress.formattedTime)
                StatBadge(icon: "wrench.and.screwdriver", value: "\(progress.toolCallCount)")
                if progress.fileReadCount > 0 {
                    StatBadge(icon: "doc.text", value: "\(progress.fileReadCount)")
                }
                if !progress.processedFiles.isEmpty {
                    StatBadge(icon: "doc.badge.ellipsis", value: "\(progress.processedFiles.count)")
                }

                // 취소 버튼
                if let onCancel = onCancel {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("작업 취소")
                }
            }
            .padding(12)
            .background(.bar)

            // 로딩 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.6), .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress.estimatedProgress)
                        .animation(.easeInOut(duration: 0.5), value: progress.estimatedProgress)
                }
            }
            .frame(height: 4)

            // 현재 활동 + 연결 경고
            VStack(spacing: 2) {
                HStack {
                    Text(progress.currentActivity)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }

                if let warning = progress.connectionWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.3))

            Divider()

            // 탭 선택
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                        if tab == .preview && !progress.partialResult.isEmpty {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // 탭 내용
            Group {
                switch selectedTab {
                case .steps:
                    stepsContent

                case .preview:
                    previewContent
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2))
        )
    }

    // MARK: - Steps Tab

    private var stepsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(progress.steps.enumerated()), id: \.element.id) { idx, step in
                        StepRow(step: step, isLast: idx == progress.steps.count - 1)
                            .id(step.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: progress.steps.count) { _, _ in
                if let lastStep = progress.steps.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastStep.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    // MARK: - Preview Tab

    private var previewContent: some View {
        Group {
            if progress.partialResult.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.cursor")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Claude가 응답을 생성하면 여기에 실시간으로 표시됩니다")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxHeight: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack {
                            Markdown(progress.partialResult)
                                .markdownTheme(.gitHub)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()

                            Color.clear
                                .frame(height: 1)
                                .id("preview-bottom")
                        }
                    }
                    .onChange(of: progress.partialResult) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("preview-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct StatBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary)
        .clipShape(Capsule())
        .foregroundStyle(.secondary)
    }
}

struct StepRow: View {
    let step: WorkStep
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 타임라인 인디케이터
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isLast && !step.isComplete ? Color.blue : (step.isComplete ? Color.green : Color.secondary))
                        .frame(width: 8, height: 8)

                    if isLast && !step.isComplete {
                        Circle()
                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 20)
                }
            }

            // 단계 내용
            HStack(spacing: 6) {
                Text(step.icon)
                    .font(.system(size: 12))
                Text(step.label)
                    .font(.system(size: 12, weight: isLast ? .medium : .regular))
                    .foregroundStyle(isLast ? .primary : .secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)

            Spacer()
        }
    }
}
