# API Key 설정 가이드

이 앱이 올바르게 동작하려면 Google Maps와 OpenAI의 API Key가 필요합니다. 보안을 위해 소스 코드에 키를 직접 입력하지 않고, 별도의 설정 파일을 사용합니다.

## 1. `Secrets.plist` 수정
Xcode 프로젝트 내의 `DigitalCane/Resources` 그룹에 있는 `Secrets.plist` 파일을 엽니다.

```xml
<key>GOOGLE_MAPS_API_KEY</key>
<string>여기에_구글_키_입력</string>
<key>OPENAI_API_KEY</key>
<string>여기에_OPENAI_키_입력</string>
```
이 부분에 본인이 발급받은 키를 붙여넣으세요.

## 2. API Key 발급 방법

### 🌏 Google Maps Platform
1. [Google Cloud Console](https://console.cloud.google.com/) 접속 및 로그인.
2. 새 프로젝트 생성.
3. **APIs & Services > Library** 이동.
4. 아래 API들을 검색하여 **Enable(사용 설정)**:
   - **Routes API** (경로 탐색용)
   - **Places API (New)** (장소 검색용)
5. **Credentials** 메뉴에서 **Create Credentials > API Key** 선택.
6. 생성된 키를 복사하여 `Secrets.plist`에 입력.

### 🧠 OpenAI (LLM)
1. [OpenAI Platform](https://platform.openai.com/) 접속 및 로그인.
2. 우측 상단 프로필 > **View API Keys**.
3. **Create new secret key** 클릭.
4. 생성된 키(sk-...)를 복사하여 `Secrets.plist`에 입력.

## ⚠️ 주의사항
- `Secrets.plist` 파일은 API Key가 포함되어 있으므로, 깃허브(GitHub) 등 공개 저장소에 **절대 커밋하지 마세요**. (`gitignore` 처리를 권장합니다.)
