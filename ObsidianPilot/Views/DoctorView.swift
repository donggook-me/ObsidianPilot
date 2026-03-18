import SwiftUI

struct DoctorView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var doctor: DoctorService

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            header
            Divider()

            // 내용
            if doctor.checks.isEmpty && !doctor.isRunning {
                emptyState
            } else {
                checkList
            }

            Divider()

            // 하단: 캐시 경로 + 이전 기록
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 16))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Doctor 모드")
                    .font(.system(size: 14, weight: .semibold))
                Text("Claude 연결 및 시스템 상태를 진단합니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let report = doctor.lastReport {
                statusBadge(report.overallStatus)
            }

            Button {
                Task {
                    await doctor.runDiagnostics(
                        claudePath: appState.claude.claudePath,
                        vaultPath: appState.claude.vaultPath,
                        baseSessionId: appState.claude.baseSessionId,
                        isClaudeReady: appState.isClaudeReady,
                        sessions: appState.sessionStore.sessions
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    if doctor.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(doctor.isRunning ? "진단 중..." : "진단 실행")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(doctor.isRunning)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "stethoscope")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("진단을 실행하면 다음을 확인합니다")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                checkItem("Claude CLI 설치 및 버전")
                checkItem("Vault 경로 및 파일 접근")
                checkItem("세션 상태 (warm-up / fork)")
                checkItem("Claude 응답 테스트")
                checkItem("최근 에러 패턴 분석")
                checkItem("파일 읽기/쓰기 권한")
            }
            .padding(.horizontal, 40)

            Text("결과는 이슈 캐시에 자동 저장되어\n개발자가 문제를 추적할 수 있습니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    private func checkItem(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Check List

    private var checkList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 요약 카드
                if let report = doctor.lastReport {
                    summaryCard(report)
                        .padding(12)
                }

                // 개별 체크
                ForEach(doctor.checks) { check in
                    checkRow(check)
                }
            }
        }
    }

    private func summaryCard(_ report: DoctorReport) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: report.overallStatus == .pass ? "checkmark.seal.fill" : report.overallStatus == .warning ? "exclamationmark.triangle.fill" : "xmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(statusColor(report.overallStatus))
                Text(report.overallStatus == .pass ? "정상" : report.overallStatus == .warning ? "주의" : "문제 발견")
                    .font(.system(size: 13, weight: .semibold))
            }

            Divider()
                .frame(height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    statLabel(icon: "checkmark.circle.fill", color: .green, count: report.passCount)
                    statLabel(icon: "exclamationmark.triangle.fill", color: .orange, count: report.warningCount)
                    statLabel(icon: "xmark.circle.fill", color: .red, count: report.failCount)
                }
                Text(report.timestamp, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(12)
        .background(statusColor(report.overallStatus).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor(report.overallStatus).opacity(0.15))
        )
    }

    private func statLabel(icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func checkRow(_ check: DoctorCheck) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // 상태 아이콘
                if check.status == .running {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: check.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(statusColor(check.status))
                        .frame(width: 16)
                }

                // 체크 이름 & 카테고리
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(check.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(check.category)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(Capsule())
                            .foregroundStyle(.tertiary)
                    }

                    Text(check.message)
                        .font(.system(size: 11))
                        .foregroundStyle(check.status == .fail ? .red : .secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // 제안 사항
            if let suggestion = check.suggestion {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(suggestion)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 38)
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.leading, 38)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Text("이슈 캐시: \(doctor.cachePath)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: doctor.cachePath)
            } label: {
                Text("Finder에서 열기")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            // 클립보드에 경로 복사
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(doctor.cachePath, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("캐시 경로 복사")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Helpers

    private func statusColor(_ status: DoctorCheck.CheckStatus) -> Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        case .running: return .blue
        }
    }

    private func statusBadge(_ status: DoctorCheck.CheckStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)
            Text(status == .pass ? "정상" : status == .warning ? "주의" : "이상")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor(status).opacity(0.1))
        .clipShape(Capsule())
    }
}
