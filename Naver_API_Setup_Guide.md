# Naver Cloud Platform API 설정 가이드

## 1. Naver Cloud Platform 회원가입

1. [Naver Cloud Platform](https://www.ncloud.com/) 접속
2. "콘솔 로그인" → 네이버 계정으로 로그인
3. 신규 가입 시 무료 크레딧 제공 (30일간)

---

## 2. Application 등록

### 2-1. Console 접속
1. 좌측 메뉴: **Services** → **AI·NAVER API** → **AI·NAVER API**
2. "Application 등록" 버튼 클릭

### 2-2. Application 정보 입력
- **Application 이름**: DigitalCane
- **Service 선택**:
  - ✅ **Maps**
    - ✅ Geocoding (주소 → 좌표)
    - ✅ Reverse Geocoding (좌표 → 주소)
    - ✅ Directions 5 (길찾기)
  - ✅ **검색** (선택 사항)
    - 🔲 지역 검색

### 2-3. 환경 추가
- **Web Dynamic Map**: ✅ (선택)
- **iOS/Android**: 번들 ID 입력
  - iOS Bundle ID: `kr.ac.kaist.assistiveailab.DigitalCane`

### 2-4. 등록 완료
- **Client ID** 복사: `YOUR_NAVER_CLIENT_ID`
- **Client Secret** 복사: `YOUR_NAVER_CLIENT_SECRET`

---

## 3. Secrets.plist 업데이트

`DigitalCane/Resources/Secrets.plist` 파일 수정:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- OpenAI (기존) -->
    <key>OPENAI_API_KEY</key>
    <string>sk-proj-...</string>
    
    <!-- Google Maps (백업용) -->
    <key>GOOGLE_MAPS_API_KEY</key>
    <string>AIza...</string>
    
    <!-- Naver Cloud Platform (신규 추가) -->
    <key>NAVER_CLIENT_ID</key>
    <string>YOUR_NAVER_CLIENT_ID</string>
    
    <key>NAVER_CLIENT_SECRET</key>
    <string>YOUR_NAVER_CLIENT_SECRET</string>
</dict>
</plist>
```

---

## 4. API 엔드포인트

### Geocoding (장소명 → 좌표)
```
GET https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode
Headers:
  X-NCP-APIGW-API-KEY-ID: {Client ID}
  X-NCP-APIGW-API-KEY: {Client Secret}
Query:
  query=서울역
```

### Directions (경로 탐색)
```
GET https://naveropenapi.apigw.ntruss.com/map-direction/v1/driving
또는
GET https://naveropenapi.apigw.ntruss.com/map-direction-15/v1/driving

** 대중교통 전용 **
실제로는 Naver의 대중교통 API가 공개되지 않음!
대안: Naver Search API "지역 검색" + 수동 경로 조합
```

---

## ⚠️ 중요: Naver API 제한 사항

**Naver는 대중교통 길찾기 API를 공개하지 않습니다.**

### 제공되는 것:
- ✅ Geocoding (주소 ↔ 좌표)
- ✅ 자동차 길찾기 (Driving Directions)
- ✅ 보행자 길찾기 (내부망 전용, 제한적)

### 제공 안 되는 것:
- ❌ 대중교통 경로 (버스/지하철)
- ❌ 실시간 버스 도착 정보

---

## 대안 솔루션

실제로 대중교통 경로를 얻으려면:

### Option A: ODsay API 병행
- Naver Geocoding (장소 검색)
- ODsay API (대중교통 경로)

### Option B: TMAP API 사용
- TMAP 단독으로 모든 기능 제공
- 무료 한도: 25,000건/월

### Option C: 공공 데이터 조합
- Naver Geocoding
- 서울시 TOPIS API (버스)
- 국토교통부 대중교통 API (지하철)
- **수동으로 경로 조합 필요 (복잡)**

---

## 추천

현재 요구사항(대중교통 경로)을 위해서는:

**TMAP API 또는 Kakao + ODsay 조합이 필수적입니다.**

Naver만으로는 대중교통 경로를 얻을 수 없습니다.
