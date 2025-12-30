# TMAP API 설정 가이드

## 1. TMAP API 회원가입

### 1-1. TMAP Mobility 개발자 사이트 접속
1. [TMAP Mobility Open Platform](https://openapi.sk.com/) 접속
2. "회원가입" 클릭
3. 이메일 인증 후 가입 완료

---

## 2. 앱 등록 및 API 키 발급

### 2-1. 앱 등록
1. 로그인 후 "내 애플리케이션" → "앱 등록" 클릭
2. **앱 정보 입력**:
   ```
   앱 이름: DigitalCane
   플랫폼: iOS
   번들 ID: kr.ac.kaist.assistiveailab.DigitalCane
   카테고리: 교통/내비게이션
   ```

### 2-2. API 선택
다음 API들을 체크:
- ✅ **POI 통합검색** (장소 검색)
- ✅ **대중교통경로안내** (대중교통 경로)
- ✅ **Geocoding** (주소 ↔ 좌표)
- ✅ **Reverse Geocoding** (좌표 → 주소)

### 2-3. 약관 동의 및 등록
- 이용약관 동의
- "등록" 버튼 클릭

### 2-4. App Key 확인
- 등록 완료 후 **App Key** 복사
- 예시: `l7xx1234567890abcdef1234567890ab`

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
    
    <!-- Google Maps (백업용으로 유지) -->
    <key>GOOGLE_MAPS_API_KEY</key>
    <string>AIza...</string>
    
    <!-- TMAP API (신규 추가) -->
    <key>TMAP_APP_KEY</key>
    <string>YOUR_TMAP_APP_KEY</string>
</dict>
</plist>
```

---

## 4. TMAP API 엔드포인트

### 4-1. POI 통합 검색 (장소 검색)
```
GET https://apis.openapi.sk.com/tmap/pois
Headers:
  appKey: {YOUR_TMAP_APP_KEY}
Query Parameters:
  searchKeyword: 서울역
  count: 5
```

**응답 예시**:
```json
{
  "searchPoiInfo": {
    "pois": {
      "poi": [{
        "name": "서울역",
        "noorLat": 37.5546788,
        "noorLon": 126.9707201,
        "upperAddrName": "서울특별시",
        "middleAddrName": "용산구"
      }]
    }
  }
}
```

### 4-2. 대중교통경로안내
```
POST https://apis.openapi.sk.com/transit/routes
Headers:
  appKey: {YOUR_TMAP_APP_KEY}
  Content-Type: application/json
Body:
{
  "startX": "126.9707201",
  "startY": "37.5546788",
  "endX": "127.0276368",
  "endY": "37.4979517",
  "lang": 0,
  "format": "json",
  "count": 10
}
```

**응답 예시**:
```json
{
  "metaData": {
    "plan": {
      "itineraries": [{
        "legs": [{
          "mode": "SUBWAY",
          "route": "4호선",
          "routeColor": "00A5DE",
          "start": {
            "name": "서울역"
          },
          "end": {
            "name": "동작역"
          },
          "stationCount": 3,
          "distance": 5432,
          "sectionTime": 7
        }]
      }]
    }
  }
}
```

---

## 5. 무료 한도 및 가격

### 무료 한도
- **월 25,000건**
- 일 평균 약 833건

### 유료 전환
- 초과 시: **건당 ₩3**
- 예: 월 30,000건 사용 시
  - 무료: 25,000건
  - 유료: 5,000건 × ₩3 = ₩15,000

### 실제 사용량 예상 (개인)
- 하루 평균 5건
- 월 150건
- **→ 완전 무료 범위**

---

## 6. API 문서

### 공식 문서
- [TMAP API 가이드](https://tmapapi.sktelecom.com/main.html)
- [대중교통 경로 API](https://tmapapi.sktelecom.com/main.html#/docs/transitRoute)
- [POI 검색 API](https://tmapapi.sktelecom.com/main.html#/docs/pois)

### 지원
- 개발자 포럼: https://openapi.sk.com/community
- 고객센터: support@sktelecom.com

---

## 7. 주요 특징 (시각장애인 지원)

### 접근성 옵션
```json
{
  "wheelchair": "Y",      // 휠체어 접근 가능 경로
  "stairInfo": "N",       // 계단 회피
  "elevatorInfo": "Y"     // 엘리베이터만 사용
}
```

### 상세 환승 정보
- 지하철 몇 호차 탑승
- 몇 번 출구로 나가기
- 환승 동선 상세 안내

### 실시간 정보
- 버스 도착 예정 시간
- 지하철 혼잡도

---

## 다음 단계

API 키 발급 완료 후:
1. `Secrets.plist`에 키 추가
2. `APIService.swift` 수정 (자동 진행 예정)
3. 테스트 실행

API 키를 발급받으셨으면 알려주세요!
