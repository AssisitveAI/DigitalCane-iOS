# 🚀 앱스토어 배포 준비 체크리스트 (DigitalCane)

앱스토어(App Store) 및 테스트플라이트(TestFlight) 배포를 위해 반드시 확인해야 할 항목들입니다.

## 1. 필수 파일 추가 (매우 중요!)
제가 심사에 필요한 필수 파일들을 **이미 생성해 두었습니다.** Xcode에서 프로젝트에 추가만 하시면 됩니다.

1.  **Xcode 실행**: `DigitalCane.xcodeproj`를 엽니다.
2.  **파일 추가**:
    - 좌측 네비게이터에서 `DigitalCane/Resources` 폴더를 우클릭 후 `Add Files to "DigitalCane"...` 선택.
    - `PrivacyInfo.xcprivacy` 파일과 `Info.plist` 파일을 선택하고 `Add` 클릭.
    - **Target Membership** 체크 확인 (DigitalCane 타겟).
    - **주의**: `Info.plist`를 추가한 후, **Build Settings**에서 `Generate Info.plist File` 항목을 `No`로 변경하고, `Info.plist File` 경로를 `DigitalCane/Resources/Info.plist`로 설정해 주세요. (이 과정이 번거롭다면 기존 설정 그대로 두고 권한 문구만 복사해도 됩니다.)

## 2. 권한 설정 (생성된 Info.plist에 포함됨)
제가 생성한 `Info.plist` 파일에는 이미 다음 권한 문구가 포함되어 있습니다.
- `NSLocationWhenInUseUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`

## 3. 앱 아이콘 (App Icon)
`Assets.xcassets` 내 `AppIcon` 항목에 모든 크기의 아이콘이 채워져 있는지 확인하세요. 하나라도 비어있으면 업로드가 거부됩니다.

## 4. 버전 및 빌드 번호
- **Targets > General > Identity** 섹션에서:
    - **Version**: `1.0.0` (출시 버전)
    - **Build**: `1` (업로드할 때마다 1씩 증가해야 함)

## 5. 서명 (Signing & Capabilities)
- **Signing**: `Automatically manage signing`이 체크되어 있고, 유효한 개발자 계정(Team)이 선택되어 있는지 확인하세요.
- **Bundle Identifier**: `kr.ac.kaist.assistiveailab.DigitalCane` (예시)가 맞는지 확인하세요.

## 6. 아카이브 및 업로드 (Archive & Upload)
1.  상단 기기 선택 메뉴에서 **"Any iOS Device (arm64)"**를 선택합니다.
2.  메뉴바: `Product` -> `Archive` 선택.
3.  아카이브 완료 후 `Organizer` 창이 뜨면 **"Distribute App"** 클릭.
4.  `TestFlight & App Store` 선택 후 안내에 따라 업로드 진행.
5.  업로드 완료 후 [App Store Connect](https://appstoreconnect.apple.com)에서 빌드 처리 상태 확인.

---
**Tip**: "Export Compliance Information" 질문이 나오면, 암호화 로직을 직접 사용하지 않으므로 보통 "No" 또는 규정 준수 관련 답변을 선택하면 됩니다. HTTPS 호출은 표준 암호화로 간주되어 별도 신고가 불필요한 경우가 많습니다.
