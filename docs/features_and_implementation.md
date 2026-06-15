# 기술 구현 및 아키텍처 상세 설명

이 문서는 **Pie Menu** 프로젝트의 핵심 기능들이 macOS 환경 하에서 어떻게 조율되고 개발되었는지, 적용된 API와 구조적 아키텍처 원리를 상세히 기술합니다.

---

## 1. Option 더블 탭 및 실시간 제어 이벤트 가로채기
* **관련 클래스**: [EventTapManager.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/EventTapManager.swift)

### 구현 메커니즘
- **Option(⌥) 키 더블 탭 감지**: 
  - `NSEvent.addGlobalMonitorForEvents` 및 `addLocalMonitorForEvents`를 활용해 시스템 수준의 `.flagsChanged` 이벤트를 관찰합니다.
  - 모디파이어 플래그에 `.option`이 단독으로 포함되었을 때의 시간차를 `Date` 객체로 역산하여, 설정된 더블 탭 임계값(`doubleTapThreshold = 0.3`초) 이하일 경우 더블 탭으로 판정해 원형 파이 메뉴를 호출합니다.
- **파이 메뉴 팝업 중 제어 이벤트 차단 (Swallowing)**:
  - 파이 메뉴 창이 활성화되어 있을 때(`isMenuOpen == true`), 마우스의 클릭이나 휠 움직임, 키보드의 입력 등을 로컬 모니터링 단에서 삼켜야(Consume) 합니다.
  - `localMouseMonitor`에 들어온 방향키(`123`, `124`)나 숫자 키(`18`~`28`), `ESC`(53) 및 스크롤 휠(`.scrollWheel`) 이벤트를 감지하여 핸들링한 뒤 **`return nil`**을 반환함으로써 맥OS 시스템의 경고음(System Beep)이 나거나 백그라운드 영역이 원치 않게 반응하는 현상을 완전히 방지합니다.

---

## 2. 윈도우 수명 주기 튜닝을 통한 설정 창 숨김 제어
* **관련 클래스**: [SettingsWindow.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/SettingsWindow.swift#L321) (`SettingsWindowController`)

### 구현 메커니즘
- **종료 현상 방지**:
  - macOS 백그라운드 에이전트 앱(`.accessory` 정책)에서는 일반 윈도우가 닫힐 때(`close()`) 윈도우가 완전히 소멸(release)되면서 앱의 메인 런루프가 멈추거나 프로세스 자체가 종료되는 이슈가 발생하기 쉽습니다.
  - 이를 위해 윈도우를 구성할 때 **`newWindow.isReleasedWhenClosed = false`** 속성을 명시적으로 적용해 닫힘 동작이 일어나도 메모리 상에서 소멸하지 않도록 보호합니다.
- **팝업 단순 숨김 (`orderOut`)**:
  - `SettingsWindowController`의 `close()` 함수 실행 시 실제 소멸 함수인 `window.close()` 대신 **`window.orderOut(nil)`**을 호출하여 창을 화면상에서만 감춥니다.
  - 창의 상단 좌측 빨간색 X 닫기 버튼이 클릭될 때에도 창이 완전히 닫히지 않고 숨겨지기만 하도록 `NSWindowDelegate`의 **`windowShouldClose(_:)`** 메서드를 커스터마이징하여 `sender.orderOut(nil)`을 호출하고 `false`를 리턴하게 구성했습니다.

---

## 3. 다중 프로필 관리와 구버전 하위 호환성 마이그레이션
* **관련 클래스**: [ConfigManager.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/ConfigManager.swift)

### 구현 메커니즘
- **구조체 고도화**:
  - 파이 메뉴 설정(`AppConfig`)을 `profiles: [ProfileConfig]` 배열과 활성 프로필 식별자 `activeProfileId: UUID`로 관리하며, 메뉴 크기 설정(`menuRadius`)은 프로필들 간의 정렬 통일성을 위해 `AppConfig` 루트 수준에 배치했습니다.
- **하위 호환성 디코딩**:
  - 기존 구버전 단일 프로필 구조인 `config.json`을 안전하게 읽어올 수 있도록 `AppConfig`에 커스텀 **`init(from:)`** 디코더를 구현했습니다.
  - 디코딩 대상 키(`CodingKeys`)를 분리하여 기존 루트에 바로 배치되어 있던 `sectors` 및 `themeColorHex` 필드가 감지되면 이를 자동으로 가로채 `"Default"` 명칭의 `ProfileConfig` 인스턴스로 마이그레이션하고 새 포맷으로 파일에 영구 갱신합니다.

---

## 4. 전면 활성 앱 매핑 및 프로필 자동 전환
* **관련 클래스**: [EventTapManager.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/EventTapManager.swift#L201), [ConfigManager.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/ConfigManager.swift#L228) (`switchProfileForApp`)

### 구현 메커니즘
- **활성 전면 앱 조회**:
  - Option 키 더블 탭 판정 직후, 파이 메뉴를 모니터 상에 띄우기 전에 **`NSWorkspace.shared.frontmostApplication`** API를 실행하여 현재 사용자가 조작 중인 활성 애플리케이션 정보를 얻어옵니다.
  - 해당 앱의 번들 식별자 `bundleIdentifier`(예: `com.apple.Safari`) 및 로컬 명칭 `localizedName`(예: `Safari`)을 조회합니다.
- **프로필 매칭 트리거**:
  - `ConfigManager` 내에 탑재된 `switchProfileForApp(bundleId:appName:)`이 호출되어 등록된 각 프로필의 `targetAppBundleId` 속성과 번들 식별자 또는 앱 이름을 1차/2차 비교 검색합니다.
  - 매칭되는 대상 프로필을 발견할 경우 해당 프로필 ID를 활성 프로필(`activeProfileId`)로 설정하여, 파이 메뉴 팝업이 전면에 뜬 앱에 어울리는 최적의 매크로 메뉴로 변하도록 연동합니다. 매칭 대상이 없을 시 `"Default"` 프로필로 자동 점프합니다.

---

## 5. 다중 액션 실행 엔진 및 가상 키보드 발송
* **관련 클래스**: [CommandRunner.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/CommandRunner.swift)

### 구현 메커니즘
- **Command (쉘 명령어)**:
  - `Process` 인스턴스를 통해 시스템의 기본 쉘인 `/bin/zsh`를 실행하고 `-c` 인자와 사용자 명령어를 연동해 비동기(`DispatchQueue.global(qos: .userInitiated)`)로 작업을 처리합니다.
- **Open App (앱 실행)**:
  - `NSWorkspace.shared.open(...)` API를 실행하여 절대 경로의 `.app`이나 앱 명칭으로 직접 런칭을 시도하고, 실패 시 zsh `open -a` 명령어로 폴백 실행합니다.
- **Shortcut (단축키 모의 입력)**:
  - `CGEvent` 및 `CGEventSource` 인터페이스를 사용하여 가상 키 이벤트를 대상 세션에 포스트(`post(tap: .cghidEventTap)`)합니다.
  - 입력 문자열(예: `"Cmd+C"`)에 포함된 모디파이어 예약 키워드들을 검출해 플래그(`CGEventFlags.maskCommand`, `maskAlternate`, `maskShift`, `maskControl`)에 병합 처리합니다.
  - 매핑 딕셔너리(`keyCodes`)를 조회하여 해당하는 영문, 숫자, 특수 기능 키들의 가상 키코드(Virtual Keycodes) 값을 도출한 뒤 Key Down 및 Key Up 이벤트를 시뮬레이션 발송합니다.

---

## 6. 파일 선택 창 연동 및 앱 메타데이터 추출
* **관련 클래스**: [SettingsWindow.swift](file:///Users/satellite/개발/MacbookSibal/Sources/MacbookSibal/SettingsWindow.swift#L233) (`selectAppFromApplicationsFolder`)

### 구현 메커니즘
- **`NSOpenPanel` 다이얼로그 구동**:
  - 설정 창 UI 내 폴더 아이콘 버튼 클릭 시 `NSOpenPanel` 인스턴스를 생성하여 애플리케이션 보관 디렉토리인 `/Applications`를 기본값으로 타겟팅합니다.
  - 파일 타입 필터에 **`UTType.application`** 마스크를 할당해 유효한 `.app` 패키지 어플리케이션 파일만 선택되도록 고정합니다.
- **번들 식별자 파싱**:
  - 사용자가 앱을 확정 선택하면, 선택된 파일의 URL 경로를 바탕으로 `Bundle(url:)`을 초기화하고 번들 식별자 속성인 `bundleIdentifier`를 자동으로 파싱해 UI 텍스트 필드에 주입시킵니다.
