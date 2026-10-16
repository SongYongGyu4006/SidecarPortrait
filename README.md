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

## 실행

```bash
swift build
.build/debug/SidecarPortrait                 # 270도 회전 (기본값)
.build/debug/SidecarPortrait --rotate 90     # 반대 방향
.build/debug/SidecarPortrait --device "내 iPad"
```

- 처음 실행하면 **화면 및 시스템 오디오 녹음** 권한이 필요해요 (시스템 설정 > 개인정보 보호 및 보안). 실행한 터미널 앱을 허용한 뒤 터미널을 다시 시작하세요.
- iPad를 가로로 든 상태에서 **회전 잠금**을 켜고, 그다음 세로로 돌려 드세요. 위아래가 거꾸로면 `--rotate`를 바꾸면 돼요.
- 창은 "Sidecar 세로" 디스플레이로 옮겨서 쓰세요. Ctrl+C로 끝내면 가상 디스플레이도 사라져요.

## 구성

| 경로 | 내용 |
| --- | --- |
| `Sources/PrivateAPI` | `CGVirtualDisplay`, SidecarCore, MonitorPanel 비공개 API를 감싼 Objective-C 래퍼 |
| `Sources/SidecarPortrait` | 가상 디스플레이 생성, 캡처, 회전해서 그리는 앱 |
| `Tools/sidecar-portrait.m` | Sidecar를 원하는 크기로 연결·해제하는 실험용 CLI |

비공개 API 시그니처는 Objective-C 런타임(`objc_copyClassNamesForImage`, `class_copyMethodList`)으로 조회했어요. Apple의 코드나 헤더는 포함하지 않았어요.

## 아직 안 되는 것

- iPad 터치·Apple Pencil 입력은 회전 변환이 없어서 미러링 창에 그대로 들어가요.
- 마우스 커서가 실제 Sidecar 디스플레이(미러링 창)로 넘어갈 수 있어요.

## 라이선스

[MIT](LICENSE)
