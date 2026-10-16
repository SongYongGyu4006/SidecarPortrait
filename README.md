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
| `Tools/sidecar-portrait.m` | Sidecar를 원하는 크기로 연결·해제하는 실험용 CLI |

비공개 API 시그니처는 Objective-C 런타임(`objc_copyClassNamesForImage`, `class_copyMethodList`)으로 조회했어요. Apple의 코드나 헤더는 포함하지 않았어요.

## 입력

- iPad 터치·Apple Pencil 입력(클릭, 드래그, 스크롤)은 미러링 창이 받아서 회전을 되돌린 뒤 "Sidecar 세로" 디스플레이의 같은 자리로 다시 보내요. 미러링 창은 클릭돼도 포커스를 가져가지 않아요.
- 일반 마우스 커서가 실제 Sidecar 디스플레이로 넘어가면 이벤트 탭이 "Sidecar 세로" 디스플레이 가장자리로 되돌려요.
- 둘 다 **손쉬운 사용** 권한이 필요해요 (시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 터미널 앱 허용). 권한이 없으면 화면 미러링만 동작해요.
- `--debug-input`을 붙이면 Sidecar 화면으로 들어온 이벤트와 변환 결과를 출력해요.

## 아직 안 되는 것

- 실제 iPad에서 입력 변환을 아직 확인하지 못했어요. 회전 수식은 90도·270도 모두 레이어 변환과 맞는지 검증했어요.
- 마우스와 iPad 입력은 "바로 전 위치가 Sidecar 밖이고 이동량이 작은가"로 구분해요. 커서가 "Sidecar 세로" 오른쪽 위 근처에 있을 때 펜슬로 Sidecar 화면 왼쪽 위를 찍으면 마우스로 오인될 수 있어요. 문제가 있으면 `--debug-input` 출력을 보고 조건을 조정해야 해요.
- 손가락 제스처(확대·회전 등 트랙패드식 제스처)와 스크롤 관성 단계(phase)는 따로 변환하지 않아요.
- 키보드 입력과 iPad의 Sidecar 사이드바·Touch Bar는 그대로예요.

## 라이선스

[MIT](LICENSE)
