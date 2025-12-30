# API Key 설정 가이드

이 앱이 올바르게 동작하려면 **Google Maps Platform**과 **Google Gemini**의 API Key가 필요합니다. 보안을 위해 소스 코드에 키를 직접 입력하지 않고, 별도의 설정 파일을 사용합니다.

## 1. `Secrets.plist` 수정
Xcode 프로젝트 내의 `DigitalCane/Resources` 그룹에 있는 `Secrets.plist` 파일을 엽니다.

```xml
<key>GOOGLE_MAPS_API_KEY</key>
<string>여기에_구글_맵스_키_입력</string>
<key>GEMINI_API_KEY</key>
<string>여기에_GEMINI_키_입력</string>
```
이 부분에 본인이 발급받은 키를 붙여넣으세요.

> **💡 팁**: GEMINI_API_KEY가 없으면 GOOGLE_MAPS_API_KEY를 Gemini용으로도 사용할 수 있습니다 (동일 GCP 프로젝트 내). 단, Google AI Studio에서 별도 발급을 권장합니다.

## 2. API Key 발급 방법

### 🌏 Google Maps Platform (지도/경로/장소)
1. [Google Cloud Console](https://console.cloud.google.com/) 접속 및 로그인.
2. 새 프로젝트 생성.
3. **APIs & Services > Library** 이동.
4. 아래 API들을 검색하여 **Enable(사용 설정)**:
   - **Routes API** (경로 탐색용)
   - **Places API (New)** (장소 검색용)
5. **Credentials** 메뉴에서 **Create Credentials > API Key** 선택.
6. 생성된 키를 복사하여 `Secrets.plist`의 `GOOGLE_MAPS_API_KEY`에 입력.

### 🧠 Google Gemini (LLM - 의도 분석)
1. [Google AI Studio](https://aistudio.google.com/) 접속 및 로그인.
2. 좌측 메뉴에서 **Get API Key** 클릭.
3. **Create API Key in new project** 또는 기존 프로젝트 선택.
4. 생성된 키를 복사하여 `Secrets.plist`의 `GEMINI_API_KEY`에 입력.

> **참고**: Gemini 2.0 Flash 모델은 무료 티어에서도 사용 가능합니다.

## ⚠️ 주의사항
- `Secrets.plist` 파일은 API Key가 포함되어 있으므로, 깃허브(GitHub) 등 공개 저장소에 **절대 커밋하지 마세요**. (`.gitignore` 처리를 권장합니다.)
