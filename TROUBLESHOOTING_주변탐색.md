# 주변 탐색 기능 문제 진단 가이드

## 🔍 문제 증상
"디지털 지팡이" 탭에서 주변 장소가 검색되지 않거나, 나침반 기능이 작동하지 않는 문제

---

## ✅ 체크리스트

### 1. API 키 설정 확인
**위치**: `DigitalCane/Resources/Secrets.plist`

필수 키가 올바르게 설정되어 있는지 확인:
```xml
<key>GOOGLE_MAPS_API_KEY</key>
<string>YOUR_ACTUAL_API_KEY</string>
```

**확인 방법**:
- Xcode 콘솔에서 "⚠️ Error: GOOGLE_MAPS_API_KEY not found" 에러 메시지 확인
- API 키가 빈 문자열("")이 아닌지 확인

---

### 2. 위치 권한 확인
**필수 권한**: "위치 사용 중 허용"

**확인 방법**:
1. 시뮬레이터/기기 **설정 > 개인정보 보호 > 위치 서비스**
2. "DigitalCane" 찾기
3. "앱 사용 중" 또는 "항상" 선택되어 있는지 확인

**앱에서 재요청**:
- 앱 삭제 후 재설치하면 권한 요청 다이얼로그 다시 표시됨

---

### 3. 시뮬레이터에서 위치 설정
시뮬레이터는 기본적으로 위치 정보가 없습니다.

**설정 방법**:
1. Xcode 메뉴 → **Debug > Simulate Location**
2. 위치 선택 (예: Seoul, South Korea)
3. 또는 Features → Location → Custom Location... 에서:
   ```
   Latitude: 37.5665
   Longitude: 126.9780
   ```

---

### 4. Google Places API 활성화 확인
Google Cloud Console에서 필수 API가 활성화되어 있는지:

**필수 API**:
- ✅ Places API (New)
- ✅ Routes API

**확인 방법**:
1. [Google Cloud Console](https://console.cloud.google.com/) 접속
2. APIs & Services → Enabled APIs
3. 위 API들이 활성화되어 있는지 확인

---

### 5. API 키 제한 설정 확인
API 키에 iOS 번들 ID 제한이 있는 경우:

**Google Cloud Console**:
1. APIs & Services → Credentials
2. API 키 클릭
3. Application restrictions:
   - **None** (제한 없음) 또는
   - **iOS apps**에서 `kr.ac.kaist.assistiveailab.DigitalCane` 추가

---

### 6. 네트워크 연결 확인
- WiFi 또는 셀룰러 데이터 연결 확인
- 시뮬레이터도 Mac의 네트워크 사용

---

### 7. 콘솔 로그 확인
Xcode 콘솔에서 다음 메시지를 확인:

**정상 작동 시**:
```
Location Updated: 37.5665, 126.9780
디지털 지팡이 활성화. 5개 장소 감지됨
```

**에러 발생 시**:
```
⚠️ Error: GOOGLE_MAPS_API_KEY not found
Places Network Error: ...
Projects API Status Code: 403 (권한 문제)
Projects API Status Code: 400 (잘못된 요청)
Fetch Error: API 오류: 403. 키 설정을 확인하세요.
```

---

## 🛠️ 해결 방법

### 문제 1: "주변에 검색된 장소가 없습니다" 표시
**원인**:
1. 위치 권한 거부됨
2. 시뮬레이터에 위치 설정 안 됨
3. 선택한 위치 주변에 실제로 장소가 없음 (드묾)

**해결**:
- 위치 권한 허용
- 시뮬레이터에서 서울/강남 등 도심 위치로 설정
- 반경을 200m → 500m로 늘려보기

---

### 문제 2: "로딩 중..." 상태에서 멈춤
**원인**:
1. Google API 키 오류
2. 네트워크 문제
3. API 할당량 초과

**해결**:
```swift
// APIService.swift의 fetchNearbyPlaces 호출 시 에러 로그 확인
// Xcode 콘솔에 "Places Network Error" 또는 "API Status Code" 출력됨
```

**임시 해결책 (테스트용)**:
`NearbyExploreView.swift`의 `fetchPlaces()` 함수에 더미 데이터 추가:
```swift
private func fetchPlaces() {
    // 테스트용 더미 데이터
    self.places = [
        Place(name: "테스트 장소 1", address: "서울시", types: [], 
              coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)),
        Place(name: "테스트 장소 2", address: "강남구", types: [], 
              coordinate: CLLocationCoordinate2D(latitude: 37.5700, longitude: 126.9800))
    ]
    startScanning()
    return
    
    // 기존 API 호출 코드...
}
```

---

### 문제 3: 나침반이 작동하지 않음
**원인**:
- 시뮬레이터는 나침반 센서 미지원 → **실제 iPhone 필요**

**확인**:
- 실제 기기에서 테스트
- 기기를 좌우로 흔들 때 콘솔에 "Heading: XXX" 로그 출력 확인

---

## 🚀 빠른 테스트 방법

### 1단계: 위치 및 API 키 확인
```bash
# Xcode에서 빌드 후 콘솔 확인
# 다음 로그가 보이는지:
Location Updated: 37.xxxx, 126.xxxx
```

### 2단계: 더미 데이터로 UI 테스트
위 "임시 해결책" 코드 추가 후:
- 앱 실행
- "디지털 지팡이" 탭 진입
- "준비됨: 2개의 장소" 표시 확인
- (실제 기기) 휴대폰 흔들면 "테스트 장소" 음성 재생

### 3단계: 실제 API 연동 테스트
더미 코드 제거 후:
- 서울 중심부 위치 설정
- 500m 반경 설정
- 콘솔에서 "디지털 지팡이 활성화. X개 장소 감지됨" 확인

---

## 📝 추가 디버깅

### APIService.swift 로그 추가
`fetchNearbyPlaces` 함수에:
```swift
print("🔍 Requesting places at: \(latitude), \(longitude), radius: \(radius)")

// API 응답 후:
print("✅ Received \(places?.count ?? 0) places")
print("📍 Places: \(places?.map { $0.name } ?? [])")
```

### LocationManager.swift 로그 확인
`didUpdateLocations` 함수의 주석 해제:
```swift
print("Location Updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
```

---

## ❓ 여전히 문제가 있다면

다음 정보를 확인해주세요:
1. **Xcode 콘솔 로그** 전체 복사
2. **Google Cloud Console** API 키 제한 설정 스크린샷
3. **앱 설정 > 위치 서비스** 스크린샷
4. **시뮬레이터인지 실제 기기인지** 명시

이 정보로 더 정확한 진단이 가능합니다!
