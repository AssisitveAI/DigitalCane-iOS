# DigitalCane iOS 앱 실행 가이드

이 프로젝트는 Xcode에서 실행할 수 있는 Swift 코드로 구성되어 있습니다. 아래 단계에 따라 프로젝트를 설정하세요.

## 1. Xcode 프로젝트 생성
1. Xcode를 실행하고 **New Project**를 선택합니다.
2. **iOS > App**을 선택합니다.
3. 프로젝트 정보를 입력합니다:
   - **Product Name**: DigitalCane
   - **Interface**: SwiftUI
   - **Life Cycle**: SwiftUI App
   - **Language**: Swift
4. 프로젝트를 생성한 폴더를 기억해둡니다.

## 2. 파일 복사 및 설정
이 저장소의 `DigitalCane` 폴더 내에 있는 파일들을 Xcode 프로젝트로 옮겨야 합니다.

1. `DigitalCane/App/DigitalCaneApp.swift` -> Xcode의 `DigitalCaneApp.swift` 내용을 덮어씁니다.
2. `DigitalCane/App/ContentView.swift` -> Xcode의 `ContentView.swift` 내용을 덮어씁니다.
3. Xcode 프로젝트 내에 `Services` 라는 그룹(폴더)을 만듭니다.
4. 아래 파일들을 드래그 앤 드롭으로 `Services` 그룹에 추가합니다:
   - `DigitalCane/Services/SpeechManager.swift`
   - `DigitalCane/Services/NavigationManager.swift`
   *추가할 때 'Copy items if needed'를 체크하세요.*

## 3. 권한 설정 (Info.plist)
음성 인식과 마이크, 위치 사용을 위해 권한 설정이 필수입니다.

1. Xcode 프로젝트 네비게이터에서 최상단 프로젝트 아이콘 클릭 -> **Targets** -> **Info** 탭으로 이동.
2. **Custom iOS Target Properties** 섹션에 아래 키들을 추가합니다.
   
   | Key | Type | Value (설명) |
   | --- | --- | --- |
   | **Privacy - Speech Recognition Usage Description** | String | 목적지 음성 입력을 위해 음성 인식이 필요합니다. |
   | **Privacy - Microphone Usage Description** | String | 음성 명령을 듣기 위해 마이크 접근이 필요합니다. |
   | **Privacy - Location When In Use Usage Description** | String | 현재 위치 기반 대중교통경로안내를 제공하기 위해 위치 정보가 필요합니다. |

## 4. 실행 (Build & Run)
1. iPhone을 Mac에 연결하거나 시뮬레이터를 선택합니다.
2. **Command + R**을 눌러 앱을 실행합니다.
3. 앱이 실행되면 마이크 및 음성 인식 권한을 허용해주세요.
4. 화면을 탭하고 목적지를 말해보세요 (예: "강남역").

## 5. 참고 사항
- 현재 `NavigationManager.swift`에는 실제 Google API 대신 "데모용 모의 데이터(Mock Data)"가 들어있습니다. 
- 실제 API 연동을 위해서는 Google Cloud Console에서 API Key를 발급받아 `Services/APIService.swift` 등을 구현해야 합니다.
