# ObsidianPilot 개발 노트

## 개요

Obsidian vault를 Claude CLI 에이전트를 통해 관리하는 macOS 네이티브 앱.
메뉴바 상주 + 독립 윈도우 형태로 동작하며, vault 정합성 검증, 파일 검증, 아이디어 제안, 메모 캡처 기능을 제공한다.

- **플랫폼**: macOS 14+ (Sonnet)
- **언어**: Swift 5.9
- **UI 프레임워크**: SwiftUI
- **빌드 시스템**: Swift Package Manager
- **외부 의존성**: MarkdownUI (gonzalezreal/swift-markdown-ui 2.4.0+)
- **코드 규모**: Swift 3,475줄 / 소스 파일 22개

---

## 프로젝트 구조

```
ObsidianPilot/
├── Package.swift                    # SPM 설정 (macOS 14+, MarkdownUI 의존)
├── build.sh                         # 릴리스 빌드 → .app 번들 → /Applications 설치
├── generate_icon.swift              # 앱 아이콘 생성 스크립트
├── ObsidianPilot/
│   ├── ObsidianPilotApp.swift       # @main 진입점 + AppState (루트 상태 관리)
│   ├── Info.plist                   # 번들 메타데이터 (URL scheme: obsidianpilot://)
│   ├── ObsidianPilot.entitlements   # 샌드박스 비활성화 (파일시스템 전체 접근)
│   │
│   ├── Models/
│   │   ├── Session.swift            # 실행 기록 데이터 모델
│   │   └── VaultFile.swift          # Vault 파일 + 카테고리 분류 모델
│   │
│   ├── Services/
│   │   ├── ClaudeService.swift      # Claude CLI 래퍼 (세션 관리, 스트리밍, 파싱)
│   │   ├── SessionStore.swift       # 세션 기록 영구 저장 (JSON, 최대 100건)
│   │   ├── SettingsService.swift    # 앱 설정 (UserDefaults)
│   │   └── VaultService.swift       # Vault 파일 탐색 및 카테고리 감지
│   │
│   ├── ViewModels/
│   │   ├── OrganizeViewModel.swift  # Organize 기능 상태 관리
│   │   ├── VerifyViewModel.swift    # Verify 기능 상태 관리
│   │   ├── IdeaViewModel.swift      # Ideas 기능 상태 관리 (포커스 모드)
│   │   ├── CaptureViewModel.swift   # Quick Capture 상태 관리
│   │   └── HistoryViewModel.swift   # 기록 필터링
│   │
│   └── Views/
│       ├── MainWindow.swift         # 탭 기반 메인 윈도우 + warm-up 상태 표시
│       ├── MenuBarView.swift        # 메뉴바 팝오버 (전체 기능 빠른 접근)
│       ├── OrganizeView.swift       # Organize 탭 UI
│       ├── VerifyView.swift         # Verify 탭 UI (HSplitView: 파일목록|결과)
│       ├── IdeaView.swift           # Ideas 탭 UI
│       ├── CaptureView.swift        # Quick Capture 탭 UI
│       ├── HistoryView.swift        # 전체 기록 탭 UI (HSplitView: 목록|상세)
│       ├── ProgressPanel.swift      # 작업 진행 표시 (단계 타임라인 + 실시간 미리보기)
│       ├── FeatureHistorySection.swift # 각 탭 하단 이전 기록 컴포넌트
│       ├── MathMarkdownView.swift   # 수학 공식 렌더링 (WKWebView + KaTeX)
│       └── SettingsView.swift       # 설정 화면
```

---

## 아키텍처

### 레이어 구조

```
┌─────────────────────────────────────────────────┐
│  SwiftUI Views                                   │
│  (OrganizeView, VerifyView, MathMarkdownView...) │
├─────────────────────────────────────────────────┤
│  ViewModels (@MainActor, ObservableObject)        │
│  각 기능별 상태 + Task로 비동기 실행               │
├─────────────────────────────────────────────────┤
│  AppState (@MainActor, ObservableObject)          │
│  모든 VM + Service 소유, Combine 변경 전파         │
├─────────────────────────────────────────────────┤
│  Services                                         │
│  ClaudeService │ SessionStore │ VaultService       │
├─────────────────────────────────────────────────┤
│  Foundation.Process → Claude CLI (외부 프로세스)    │
│  stdout stream-json → StreamParser → UI            │
└─────────────────────────────────────────────────┘
```

### 상태 전파 패턴

```
ViewModel.objectWillChange
    ↓ (Combine sink)
AppState.objectWillChange
    ↓ (@EnvironmentObject)
SwiftUI View 갱신
```

AppState가 ViewModel을 plain `var`로 소유하므로 (`@Published`가 아님), VM 내부의 `@Published` 변경이 자동으로 View까지 전파되지 않는다. 이를 해결하기 위해 `forwardChanges(from:)` 패턴으로 각 VM의 `objectWillChange`를 AppState의 `objectWillChange`로 포워딩한다.

```swift
private func forwardChanges<T: ObservableObject>(from child: T) {
    child.objectWillChange
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)
}
```

---

## Claude 에이전트 세션 설계

### 세션 아키텍처

```
앱 시작
  │
  ▼
┌─────────────────────────────────────┐
│  Base Session (warm-up)              │
│  claude -p --session-id <UUID>       │
│  CLAUDE.md + HOME.md + MOC 읽기     │
│  → vault 구조 전체 파악              │
│  → 세션 디스크 저장 (재사용 위해)     │
└─────────────┬───────────────────────┘
              │ baseSessionId 보관
              │
    ┌─────────┼──────────┬────────────┐
    ▼         ▼          ▼            ▼
 Organize   Verify    Ideas       Capture
 --resume   --resume  --resume    --resume
 <UUID>     <UUID>    <UUID>      <UUID>
 --fork     --fork    --fork      --fork
 -session   -session  -session    -session
```

**핵심 원리:**
1. 앱 시작 시 `warmUp()`이 경량 프롬프트로 vault 구조 파악 세션을 생성
2. 이후 모든 작업은 `--resume <baseId> --fork-session`으로 base 세션을 fork
3. fork된 세션은 base의 대화 히스토리(vault 구조 정보)를 물려받되 독립적
4. base 세션은 불변 — 동시 실행해도 충돌 없음

**폴백 안전장치:**
- warm-up 실패 → `baseSessionId = nil` → `--no-session-persistence` 독립 모드
- fork 실행 에러 → `baseSessionId = nil` 초기화 → 다음 작업은 독립 실행

### CLI 인자 빌드 (`buildArguments`)

```swift
// base 세션 있을 때
["--resume", sid, "--fork-session", "-p", "--output-format", "stream-json",
 "--verbose", "--permission-mode", "acceptEdits", prompt]

// base 세션 없을 때 (폴백)
["-p", "--output-format", "stream-json", "--verbose",
 "--permission-mode", "acceptEdits", "--no-session-persistence", prompt]
```

### 성능 최적화 효과

| 구간 | warm-up 없음 | warm-up 있음 |
|------|-------------|-------------|
| CLAUDE.md 읽기 | 매번 도구 호출 | fork에 포함 (스킵) |
| HOME.md + MOC | 매번 도구 호출 | fork에 포함 (스킵) |
| vault 구조 파악 | 매번 반복 | fork에 포함 (스킵) |
| API 연결 | 매번 새 연결 | 매번 새 연결 (동일) |

**트레이드오프**: fork 세션의 입력 토큰에 warm-up 대화가 포함되어 토큰 비용 증가, 그러나 도구 호출 생략으로 체감 속도 감소.

---

## 스트리밍 파서 설계 (StreamParser)

Claude CLI의 `--output-format stream-json` 출력을 실시간 파싱하여 UI에 진행 상황을 표시.

### 이벤트 흐름

```
Claude CLI stdout (줄 단위 JSON)
    │
    ▼
StreamParser.parse(line)
    │ "assistant"           → StreamEvent(.thinking)
    │ "content_block_start" → StreamEvent(.toolUse) + finalizeTool()
    │ "content_block_delta" → toolInputBuffer 누적 또는 StreamEvent(.text)
    │ "content_block_stop"  → finalizeTool() → StreamEvent(.toolDetail)
    │ "result"              → StreamEvent(.result)
    │
    ▼
StreamProgress.addEvent()  (@MainActor)
    │ steps[] 갱신, toolCallCount++, partialResult 누적
    │
    ▼
ProgressPanel UI (단계 타임라인 + 실시간 미리보기)
```

### 파일 경로 추출

도구 입력이 `input_json_delta`로 청크 단위로 전달되므로, `toolInputBuffer`에 누적 후 `content_block_stop` 시점에 JSON 파싱하여 `file_path`, `path`, `pattern`, `command` 등을 추출.

```
input_json_delta: {"file → buffer: {"file
input_json_delta: _path": "/Us → buffer: {"file_path": "/Us
input_json_delta: ers/..."}    → buffer: {"file_path": "/Users/..."}
content_block_stop → finalizeTool() → extractFilePath() → "work/cle/diary/2603.md"
```

---

## 주요 기능별 설계

### 1. Organize (vault 정합성 검증)

- **VM**: `OrganizeViewModel` — 카테고리 선택 (auto/all/work/math/invest/books/root)
- **프롬프트**: `/organize [category]` 스킬 호출 + 비대화형 지시
- **Claude 동작**: CLAUDE.md 규칙 기반으로 frontmatter, MOC 백링크, 파일 위치 검증 및 수정
- **UI**: 결과를 MathMarkdownView로 렌더링 + FeatureHistorySection

### 2. Verify (파일 내용 검증)

- **VM**: `VerifyViewModel` — 최근 72시간 파일 목록 + 선택
- **프롬프트**: 파일 경로 전달 → 사실 정확성, 논리 일관성, 빠진 맥락, 탐구 제안 4항목 검증
- **UI**: HSplitView (파일 목록 | 검증 결과)

### 3. Ideas (지식 연결 아이디어)

- **VM**: `IdeaViewModel` — 포커스 모드 (전체/Bridge/투자/독서)
- **포커스별 프롬프트**:
  - `bridge`: 수학 → 업무(3D Vision, 로봇공학) 연결
  - `invest`: 업무 도메인 지식 → 투자 인사이트
  - `books`: 독서 인사이트 → 다른 카테고리 연결
  - `all`: 전체 카테고리 교차 분석
- **UI**: 결과 + 히스토리

### 4. Capture (빠른 메모 캡처)

- **VM**: `CaptureViewModel` — 텍스트 입력 → 자동 분류 + 저장
- **프롬프트**: 텍스트 분석 → 카테고리 판단 → 네이밍 컨벤션 적용 → 파일 생성 → MOC 백링크
- **UI**: TextEditor + 실행 버튼 + 결과 표시

### 5. History (세션 기록)

- **VM**: `HistoryViewModel` — 기능별 필터링
- **Store**: `SessionStore` — JSON 영구 저장 (최대 100건)
- **UI**: HSplitView (필터+목록 | 상세 결과)

---

## 렌더링 시스템

### MathMarkdownView (수학 공식 지원)

WKWebView 기반으로 마크다운 + LaTeX 수학 공식을 렌더링.

**기술 스택:**
- **marked.js** (CDN): 마크다운 → HTML 변환
- **KaTeX** (CDN): LaTeX 수학 공식 렌더링
- **CSS**: GitHub 스타일, 다크/라이트 모드 자동 대응 (`prefers-color-scheme`)

**수학 블록 보호 메커니즘:**
1. 마크다운 파싱 전에 `$...$`, `$$...$$`, `\(...\)`, `\[...\]` 블록을 플레이스홀더로 치환
2. marked.js로 마크다운 파싱 (수학 블록 안의 `_`, `*` 등이 깨지지 않음)
3. 플레이스홀더를 원본 수학 블록으로 복원
4. KaTeX `renderMathInElement()`로 수학 공식 렌더링

**콘텐츠 전달:**
- Swift → JavaScript: UTF-8 base64 인코딩 → `TextDecoder`로 디코딩 (유니코드 안전)
- 콘텐츠 변경 감지: `Coordinator.lastContent` 비교로 불필요한 리로드 방지

**적용 범위:**

| 컴포넌트 | 렌더러 | 이유 |
|---------|--------|------|
| OrganizeView 결과 | MathMarkdownView | 최종 결과, 수학 공식 포함 가능 |
| VerifyView 결과 | MathMarkdownView | 최종 결과 |
| IdeaView 결과 | MathMarkdownView | 최종 결과 |
| HistoryView 상세 | MathMarkdownView | 과거 세션 결과 |
| FeatureHistorySection 세션 | MathMarkdownView | 과거 세션 결과 |
| ProgressPanel 미리보기 | MarkdownUI (SwiftUI) | 실시간 스트리밍 중 빈번한 업데이트 |
| CaptureView 결과 | MarkdownUI (SwiftUI) | 간단한 결과 표시 |

### ProgressPanel (진행 표시)

두 개의 탭으로 구성:
- **진행 단계**: 타임라인 형태로 각 도구 호출 단계 표시 (아이콘 + 파일 경로)
- **실시간 미리보기**: Claude 응답이 생성되는 대로 MarkdownUI로 렌더링

상단 통계 뱃지: 경과 시간, 도구 호출 수, 파일 읽기 수, 처리 파일 수

---

## UI 설계 패턴

### 메뉴바 + 윈도우 이중 인터페이스

- **MenuBarExtra**: 앱 상시 상주, 빠른 실행 (카테고리 선택 → 바로 실행)
- **Window**: 상세 결과 확인, 기록 열람, 설정
- **연동**: URL scheme `obsidianpilot://` + `openWindow(id: "main")`

### 알림 시스템

- 작업 완료 시 앱이 비활성 상태면 macOS 알림 발송
- `UNUserNotificationCenter` 사용
- 1초 간격 타이머로 `isRunning` 상태 변화 감지

---

## 해결된 기술적 이슈

### 1. ObservableObject 전파 실패 (핵심 버그)

**증상**: ViewModel의 `@Published` 프로퍼티 변경이 View에 반영되지 않음 (버튼 비활성화 안 됨, 결과 표시 안 됨)

**원인**: AppState가 ViewModel을 `var organizeVM`으로 소유 (`@Published`가 아님). SwiftUI는 AppState의 `objectWillChange`만 감시하는데, VM 내부 변경은 AppState의 `objectWillChange`를 트리거하지 않음.

**해결**: Combine `sink`로 각 VM의 `objectWillChange`를 AppState로 포워딩.

### 2. Actor Isolation 에러

**증상**: `StreamProgress.shortenPath()` (static, @MainActor) 를 `StreamParser.finalizeTool()` (non-isolated) 에서 호출 시 컴파일 에러.

**해결**: `shortenVaultPath()`를 free function으로 추출.

### 3. HSplitView 오른쪽 패널 축소

**증상**: VerifyView, HistoryView에서 오른쪽 패널이 최소 크기로 축소되어 콘텐츠가 보이지 않음.

**해결**: `.frame(minWidth: 300, idealWidth: 450)` 명시.

### 4. 중첩 Claude 세션 방지

**증상**: Claude Code 내에서 Claude CLI를 호출하면 `CLAUDECODE` 환경변수로 인해 중첩 감지 에러 발생.

**해결**: Process 환경변수에서 `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` 제거.

```swift
var env = ProcessInfo.processInfo.environment
env.removeValue(forKey: "CLAUDECODE")
env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
process.environment = env
```

---

## 빌드 및 배포

### 빌드 명령

```bash
cd /Users/dongguk/Desktop/ObsidianPilot
swift build -c release        # 릴리스 빌드
bash build.sh                 # .app 번들 생성 + /Applications 설치
```

### build.sh 동작

1. `swift build -c release`
2. `.app` 번들 디렉토리 구조 생성 (Contents/MacOS, Contents/Resources)
3. 실행 파일, Info.plist, AppIcon.icns, Asset 번들 복사
4. `/Applications/ObsidianPilot.app`으로 설치

### 알려진 빌드 경고

```
warning: stored property 'vaultPath' of 'Sendable'-conforming class
'ClaudeService' is mutable; this is an error in the Swift 6 language mode
```

`ClaudeService`가 `Sendable`인데 `vaultPath`와 `baseSessionId`가 mutable. Swift 6에서는 에러가 됨. 해결 방안: `@MainActor` 적용 또는 `nonisolated(unsafe)` 사용.

---

## 데이터 모델

### Session

```swift
struct Session: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let feature: String       // "organize" | "verify" | "ideas" | "capture"
    let input: String         // 요청 요약 (카테고리명, 파일명, 텍스트 미리보기)
    let result: String        // Claude 전체 응답 (마크다운)
    var isSuccess: Bool       // 성공/실패
    var durationSeconds: Int? // 소요 시간
}
```

### VaultFile

```swift
struct VaultFile: Identifiable, Hashable {
    let name: String          // "2603.md"
    let relativePath: String  // "work/cle/diary/2603.md"
    let fullPath: String      // "/Users/dongguk/Desktop/obsidian/work/cle/diary/2603.md"
    let category: VaultCategory  // .work | .math | .invest | .books | .bridges | .root
    let modifiedDate: Date
}
```

### VaultCategory

```swift
enum VaultCategory: String, CaseIterable {
    case work, math, invest, books, bridges, root
    var icon: String { ... }      // SF Symbol
    var organizeArg: String { ... } // CLI 인자
}
```

---

## 파일별 코드 라인 수 (소스 파일만)

| 파일 | 줄 수 | 역할 |
|------|------|------|
| ClaudeService.swift | 706 | Claude CLI 래퍼 + 스트리밍 파서 |
| MenuBarView.swift | 456 | 메뉴바 UI |
| ObsidianPilotApp.swift | 222 | 앱 진입점 + AppState |
| MathMarkdownView.swift | 114 | 수학 공식 렌더링 |
| CaptureView.swift | 114 | 캡처 UI |
| IdeaViewModel.swift | 120 | Ideas VM |
| ProgressPanel.swift | 274 | 진행 표시 |
| FeatureHistorySection.swift | 170 | 기록 컴포넌트 |
| HistoryView.swift | 146 | 기록 탭 |
| VerifyView.swift | 127 | 검증 탭 |
| OrganizeView.swift | 99 | 정리 탭 |
| IdeaView.swift | 111 | 아이디어 탭 |
| VaultService.swift | 80 | 파일 탐색 |
| SessionStore.swift | 76 | 세션 저장 |
| VaultFile.swift | 67 | 파일 모델 |
| Session.swift | 62 | 세션 모델 |
| MainWindow.swift | 72 | 메인 윈도우 |
| SettingsView.swift | 53 | 설정 UI |
| VerifyViewModel.swift | 47 | 검증 VM |
| CaptureViewModel.swift | 47 | 캡처 VM |
| OrganizeViewModel.swift | 53 | 정리 VM |
| HistoryViewModel.swift | 23 | 기록 VM |
| SettingsService.swift | 18 | 설정 서비스 |
| **합계** | **~3,475** | |

---

## 향후 개선 가능 사항

### 성능
- **Direct API 호출**: Claude CLI 대신 Anthropic API를 URLSession으로 직접 호출하면 프로세스 생성 오버헤드 제거 + prompt caching으로 vault 컨텍스트 비용 절감
- **Agent SDK 도입**: Python/TypeScript Agent SDK를 통한 장기 실행 에이전트 구현

### 기능
- KaTeX/marked.js CDN 의존 제거 → 앱 번들에 내장 (오프라인 지원)
- CaptureView에서도 MathMarkdownView 적용
- 세션 간 diff 비교 (이전 organize 결과와 현재 비교)

### 코드 품질
- `ClaudeService`의 `Sendable` 적합성 수정 (Swift 6 대비)
- ProgressPanel의 실시간 미리보기도 MathMarkdownView로 전환 (WebView 점진적 업데이트 구현 필요)
