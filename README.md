# SidecarPortrait

iPad Sidecar를 **세로 모드**로 쓰기 위한 실험용 macOS 앱.

> **Apple과 무관한 비공식 프로젝트예요.** "Sidecar", "iPad", "macOS"는 Apple Inc.의 상표예요.
> macOS의 비공개 API를 쓰므로 macOS 업데이트로 언제든 동작하지 않을 수 있고, 동작을 보장하지 않아요.
> Mac App Store 배포는 불가능해요.

## 왜 이렇게 만들었나

- macOS 쪽에서는 SidecarCore의 `connectToDevice:withConfig:completion:`에 세로 `size`를 넘기면 세로 디스플레이(1024×1366)를 만들 수 있어요.
- 하지만 iPad의 Sidecar 앱은 받은 화면을 항상 **가로 캔버스** 안에 맞춰 그려요. 그래서 세로 스트림을 보내면 가운데에 작게 줄어들어요.
- Sidecar 디스플레이 회전(`MPDisplay setOrientation:`)은 macOS가 거부해요 (`canChangeOrientation = NO`).

그래서 이 앱은 다음 순서로 동작해요.

1. Sidecar를 기본 가로(1366×1024 @2x)로 연결해요.
2. `CGVirtualDisplay`(비공개 API)로 세로 가상 디스플레이 "Sidecar 세로"(1024×1366 @2x)를 만들어요.
3. ScreenCaptureKit으로 가상 디스플레이를 캡처해요.
4. 캡처한 화면을 Sidecar 디스플레이 위 전체화면 창에 90도 돌려 그려요.

## 요구 사항

- macOS 15 이상, Apple Silicon Mac (macOS 27에서 테스트)
- Sidecar를 지원하는 iPad (iPad Pro 12.9인치 5세대에서 테스트)
- Xcode 또는 Command Line Tools (Swift 6)

## 앱으로 실행 (권장)

```bash
Scripts/build-app.sh --install   # ~/Applications/SidecarPortrait.app 생성
```

- 그다음부터는 Finder나 Spotlight에서 **SidecarPortrait**를 열면 돼요. Dock 아이콘 대신 메뉴 막대에 iPad 아이콘이 생기고, 거기서 종료해요.
- 처음 실행할 때 **화면 및 시스템 오디오 녹음**, **손쉬운 사용** 권한을 SidecarPortrait에 허용한 뒤 다시 실행하세요.
- 키체인에 Apple Development 인증서가 있으면 그것으로 서명해서, 다시 빌드해도 권한이 유지돼요. 없으면 ad-hoc 서명이라 빌드할 때마다 다시 허용해야 할 수 있어요. 다른 인증서는 `SIGN_IDENTITY="..." Scripts/build-app.sh`로 지정해요.
- 회전 방향은 `defaults write io.github.songyonggyu4006.SidecarPortrait rotate -int 90`으로 바꿔요 (기본 270).
- `--install` 없이 실행하면 `build/SidecarPortrait.app`만 만들어요.

## 터미널에서 실행

```bash
swift build
.build/debug/SidecarPortrait                 # 270도 회전 (기본값)
.build/debug/SidecarPortrait --rotate 90     # 반대 방향
.build/debug/SidecarPortrait --device "내 iPad"
.build/debug/SidecarPortrait --debug-input   # 입력 이벤트 로그
```

- 처음 실행하면 **화면 및 시스템 오디오 녹음** 권한이 필요해요 (시스템 설정 > 개인정보 보호 및 보안). 실행한 터미널 앱을 허용한 뒤 터미널을 다시 시작하세요.
- iPad를 가로로 든 상태에서 **회전 잠금**을 켜고, 그다음 세로로 돌려 드세요. 위아래가 거꾸로면 `--rotate`를 바꾸면 돼요.
- 창은 "Sidecar 세로" 디스플레이로 옮겨서 쓰세요. Ctrl+C로 끝내면 가상 디스플레이도 사라져요.

## 구성

| 경로 | 내용 |
| --- | --- |
| `Sources/PrivateAPI` | `CGVirtualDisplay`, SidecarCore, MonitorPanel 비공개 API를 감싼 Objective-C 래퍼 |
| `Sources/SidecarPortrait` | 가상 디스플레이 생성, 캡처, 회전해서 그리는 앱 |
| `Sources/UsageDashboard` | 가로 Sidecar 화면에 띄우는 Claude·Gemini 사용량 대시보드 |
| `Scripts/build-app.sh` | `.app` 번들을 만들고 서명하는 스크립트 |
| `Tools/sidecar-portrait.m` | Sidecar를 원하는 크기로 연결·해제하는 실험용 CLI |

비공개 API 시그니처는 Objective-C 런타임(`objc_copyClassNamesForImage`, `class_copyMethodList`)으로 조회했어요. Apple의 코드나 헤더는 포함하지 않았어요.

## 입력

- iPad 터치·Apple Pencil 입력(클릭, 드래그, 스크롤)은 미러링 창이 받아서 회전을 되돌린 뒤 "Sidecar 세로" 디스플레이의 같은 자리로 다시 보내요. 미러링 창은 클릭돼도 포커스를 가져가지 않아요.
- 일반 마우스 커서가 실제 Sidecar 디스플레이로 넘어가면 이벤트 탭이 "Sidecar 세로" 디스플레이 가장자리로 되돌려요.
- 둘 다 **손쉬운 사용** 권한이 필요해요 (시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 터미널 앱 허용). 권한이 없으면 화면 미러링만 동작해요.
- `--debug-input`을 붙이면 Sidecar 화면으로 들어온 이벤트와 변환 결과를 출력해요.

## 아직 안 되는 것

- 실제 iPad에서 입력 변환을 아직 확인하지 못했어요. 회전 수식은 90도·270도 모두 레이어 변환과 맞는지 검증했어요.
- 마우스와 iPad 입력은 "직전 커서가 Sidecar 밖에 있었고, 거기서 160pt 안쪽으로 이어서 들어왔는가"로 구분해요. 커서가 이미 세로 화면 모서리(270도면 오른쪽 위, 90도면 오른쪽 아래)에 있을 때 같은 모서리를 iPad로 찍으면 마우스로 오인될 수 있어요. `--debug-input`은 이벤트의 0이 아닌 필드를 모두 찍으니, iPad 입력만의 표시를 찾으면 더 정확하게 구분할 수 있어요.
- 손가락 제스처(확대·회전 등 트랙패드식 제스처)와 스크롤 관성 단계(phase)는 따로 변환하지 않아요.
- 키보드 입력과 iPad의 Sidecar 사이드바·Touch Bar는 그대로예요.

## AI 사용량 대시보드 (UsageDashboard)

iPad를 **가로** Sidecar로 연결해서 화면 전체에 Claude와 Antigravity(또는 Gemini 앱) 사용량을 띄우는 별도 앱이에요.

```bash
Scripts/build-app.sh UsageDashboard --install   # ~/Applications/UsageDashboard.app
```

- **계정 한도(모든 기기 합산)**: claude.ai와 Gemini의 공식 사용량 페이지(`claude.ai/settings/usage`, `gemini.google.com/usage`)를 보이지 않는 웹 뷰로 5분마다 열어 "n% 사용됨"과 초기화 시각만 읽어 원형 게이지로 그려요.
  - 처음 한 번 메뉴 막대 아이콘 → **Claude 로그인…**, **Gemini 로그인…**에서 직접 로그인하고 창을 닫으세요. 로그인 정보는 이 앱 전용 웹 저장소에만 남고, 메뉴의 **로그아웃**으로 지울 수 있어요.
  - 다른 앱의 토큰이나 키체인은 읽지 않아요. 페이지 구조가 바뀌면 "사용량 표시를 찾지 못했어요"가 떠요. 주소는 `defaults write io.github.songyonggyu4006.UsageDashboard claudeUsageURL <주소>`(또는 `geminiUsageURL`)로 바꿀 수 있어요.
- **Antigravity 한도**: Antigravity는 Gemini 앱(채팅)과 한도가 따로 있고 웹 페이지가 없어서, 공식 [Antigravity CLI](https://antigravity.google/docs/cli-getting-started)의 `agy -p /usage`를 5분마다 빈 임시 폴더에서 실행해 읽어요(대화 기록은 남지 않아요). 5시간·주간 한도마다 가장 많이 쓴 줄(모델별 한도 포함)과, 실제로 쓴 다른 한도 하나를 보여 줘요. 먼저 CLI를 설치하고 한 번 로그인해 두세요.

  ```bash
  curl -fsSL https://antigravity.google/cli/install.sh | bash
  agy   # 처음 한 번 실행해서 로그인
  ```

  오른쪽 칸은 메뉴 막대 아이콘의 **오른쪽 칸**에서 Antigravity(기본)와 Gemini 앱(채팅) 중에 고를 수 있어요.
- **화면 스타일**: 레트로 픽셀, 미니멀, 네온 사이버펑크, 자동차 계기판 4가지에 각각 라이트·다크 모드가 있어요. 메뉴 막대 아이콘의 **화면 스타일**, **화면 모드**에서 고르거나 iPad 화면을 탭하면 다음 스타일로 바뀌어요. 고른 값은 다음 실행에도 유지돼요.
- **사용률 추이**: 읽어 온 세션·주간 %를 시각과 함께 `~/Library/Application Support/UsageDashboard/history.json`에 기록해서(8일 보관) 아래쪽에 현재(24시간)·주간(7일) 그래프로 그려요. 값이 계정 기준이라 다른 기기 사용분도 반영돼요. 값이 크게 떨어지면 초기화로 보고 ↺로 표시하고, 대시보드가 20분 넘게 꺼져 있던 구간은 비워 둬요. 각 한도에는 초기화까지 남은 시간도 함께 보여요.
- Sidecar가 연결돼 있지 않으면 첫 번째 iPad를 연결하고, 종료할 때 연결을 끊어요. 기기는 `--device "iPad 이름"`으로 고를 수 있어요. SidecarPortrait와 같은 Sidecar 화면을 쓰므로 둘을 함께 실행하지 마세요.
- 확인용 옵션: `--window`(지금 화면에 창으로), `--snapshot dash.png`(1366×1024 PNG 저장, `--style retro|minimal|neon|gauge`·`--appearance light|dark`와 함께 쓰면 그 화면으로 저장), `--dump-account claude|gemini|antigravity out.txt`(사용량 페이지에서 읽은 글자 저장, 계정 정보가 들어 있을 수 있으니 공유하지 마세요). 로그인 정보가 앱 번들 ID에 묶여 있어서 `--dump-account`는 `build/UsageDashboard.app/Contents/MacOS/UsageDashboard`로 실행하세요.

## 라이선스

[MIT](LICENSE)
