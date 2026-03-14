# ObsidianPilot

Claude Code CLI를 활용하여 Obsidian Vault를 스마트하게 관리하는 macOS 네이티브 앱

## Features

- **Capture (캡처)**: 메모, 아이디어, 학습 내용을 입력하면 Claude가 자동으로 카테고리를 분류하여 vault에 저장
- **Organize (정리)**: vault 파일을 카테고리별로 자동 분류 및 정리, 후속 지시 가능
- **Verify (검증)**: 노트 내용의 정확성, 논리적 일관성, 누락 정보를 AI가 검토
- **Ideas (아이디어)**: vault 내 노트 간 연결점 발견, 학습 갭 분석, 크로스 카테고리 인사이트
- **History (기록)**: 모든 AI 작업 세션의 이력 관리
- **실시간 스트리밍**: Claude의 응답을 실시간으로 미리보기
- **메뉴바 앱**: 메뉴바에서 빠르게 접근 가능
- **Claude 사용량 모니터링**: 세션 비용, 토큰 사용량, 요금제 정보 표시

## Prerequisites (사전 준비)

1. **macOS 14.0 (Sonoma)** 이상
2. **Xcode 16.0** 이상
3. **Obsidian** - vault 폴더가 설정되어 있어야 함
4. **Claude Code CLI** - Anthropic의 Claude CLI가 설치되어 있어야 함
   - 설치: `npm install -g @anthropic-ai/claude-code` or https://docs.anthropic.com/en/docs/claude-code
   - `claude` 명령어가 터미널에서 실행 가능해야 함
   - Claude Pro/Max 구독 필요

## Installation (설치)

### 방법 1: Xcode로 빌드

```bash
git clone <repository-url>
cd ObsidianPilot
open ObsidianPilot.xcodeproj
# Xcode에서 Run (⌘R)
```

### 방법 2: xcodebuild 사용

```bash
git clone <repository-url>
cd ObsidianPilot
xcodebuild -project ObsidianPilot.xcodeproj -scheme ObsidianPilot -configuration Release build
```

빌드된 앱은 `~/Library/Developer/Xcode/DerivedData/ObsidianPilot-*/Build/Products/Release/ObsidianPilot.app`에 위치합니다.

### 방법 3: XcodeGen 사용

```bash
brew install xcodegen
cd ObsidianPilot
xcodegen generate
open ObsidianPilot.xcodeproj
```

## Setup (초기 설정)

앱을 처음 실행하면 온보딩 화면이 나타납니다:

1. **Vault 선택**: Obsidian vault 폴더 경로를 지정합니다. `.obsidian` 폴더가 있는 디렉토리를 선택하세요.
2. **Claude CLI 설정**: Claude CLI 실행 파일 경로를 확인합니다. 자동 감지되지 않으면 수동으로 지정하세요.
   - 일반적인 경로: `~/.local/bin/claude`, `/usr/local/bin/claude`
3. **연결 테스트**: Claude CLI가 정상 동작하는지 테스트합니다.

설정은 나중에 Settings (⌘,)에서 변경할 수 있습니다.

## Usage (사용법)

### 캡처 (메인 기능)

1. 메인 화면의 텍스트 입력 영역에 메모할 내용을 입력
2. `저장` 버튼 클릭 (또는 ⌘+Return)
3. Claude가 내용을 분석하여 적절한 카테고리로 자동 분류 후 vault에 저장

### 도구 패널

메인 화면 하단의 빠른 도구 버튼 또는 우측 사이드바 토글로 접근:

- **정리**: 카테고리를 선택하고 실행하면 vault 파일을 자동 정리
- **검증**: 파일을 선택하여 내용의 정확성을 검증
- **아이디어**: 대화형으로 vault의 지식 연결점을 탐색
- **기록**: 이전 작업 이력 확인

### 메뉴바

상단 메뉴바의 🧠 아이콘을 클릭하면 빠른 접근 팝오버가 표시됩니다.

## Architecture (기술 구조)

```
ObsidianPilot/
├── ObsidianPilotApp.swift    # 앱 진입점, AppState, AppDelegate
├── Models/
│   ├── Session.swift          # 작업 세션 데이터 모델
│   └── VaultFile.swift        # Vault 파일 모델 + 카테고리 매핑
├── Services/
│   ├── ClaudeService.swift    # Claude CLI 연동 (스트리밍)
│   ├── VaultService.swift     # Obsidian Vault 파일 관리
│   ├── SessionStore.swift     # 세션 이력 저장소
│   └── SettingsService.swift  # 설정 관리 (UserDefaults)
├── ViewModels/
│   ├── OrganizeViewModel.swift
│   ├── VerifyViewModel.swift
│   ├── IdeaViewModel.swift
│   ├── CaptureViewModel.swift
│   └── HistoryViewModel.swift
└── Views/
    ├── MainWindow.swift       # 메인 화면 (Capture 중심)
    ├── OnboardingView.swift   # 초기 설정 마법사
    ├── OrganizeView.swift     # 파일 정리 도구
    ├── VerifyView.swift       # 내용 검증 도구
    ├── IdeaView.swift         # 아이디어 탐색 도구
    ├── HistoryView.swift      # 세션 기록
    ├── CaptureView.swift      # 캡처 뷰 (독립)
    ├── SettingsView.swift     # 설정 화면
    ├── MenuBarView.swift      # 메뉴바 팝오버
    ├── ClaudeStatusPanel.swift # Claude 상태/사용량 패널
    ├── ProgressPanel.swift    # 실시간 진행 상황
    ├── MathMarkdownView.swift # 마크다운+수식 렌더러
    └── FeatureHistorySection.swift # 기능별 이력 컴포넌트
```

## How It Works (동작 원리)

ObsidianPilot은 Claude Code CLI(`claude` 명령어)를 `--output-format stream-json` 옵션으로 실행하여 AI 기능을 제공합니다.

1. 사용자 입력을 받으면 vault 구조와 함께 Claude에 프롬프트 전송
2. Claude의 응답을 실시간 스트리밍으로 파싱하여 진행 상황 표시
3. 결과를 마크다운으로 렌더링하고 세션 이력에 저장
4. 파일 생성/이동/수정은 Claude가 vault 내에서 직접 수행

## Troubleshooting (문제 해결)

### Claude CLI를 찾을 수 없는 경우

```bash
# Claude CLI 위치 확인
which claude
# 일반적인 설치 경로
ls -la ~/.local/bin/claude
ls -la /usr/local/bin/claude
```

### "독립 모드"로 표시되는 경우

- Claude CLI 경로가 올바른지 확인 (Settings ⌘,)
- Claude CLI가 정상 실행되는지 터미널에서 테스트: `claude --version`
- Claude API 키 또는 구독이 유효한지 확인

### 빌드 오류

- Xcode 16.0 이상인지 확인
- macOS 14.0 이상 타겟인지 확인
- SPM 패키지 resolve: `File > Packages > Resolve Package Versions`

## Dependencies (의존성)

- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) - 마크다운 렌더링

## License

MIT
