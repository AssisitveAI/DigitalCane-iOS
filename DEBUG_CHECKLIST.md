# 주변 탐색 기능 디버깅 체크리스트

## 🔧 단계별 확인

### 1단계: 앱 빌드 및 실행
```bash
# Xcode에서 빌드 후 시뮬레이터 또는 실제 기기에서 실행
```

---

### 2단계: Xcode 콘솔에서 로그 확인

앱 실행 후 "디지털 지팡이" 탭 진입 시 **반드시** 나타나야 하는 로그:

#### ✅ 정상 작동 시 로그 순서:
```
1. 📍 Location Updated: 37.5665, 126.9780
   → LocationManager가 GPS 좌표를 받았음

2. 🔍 [NearbyPlaces] Requesting places at: (37.5665, 126.9780), radius: 200.0m
   → Google Places API 요청 시작

3. ✅ [NearbyPlaces] Received 15 places
   → API 응답 성공

4. 📍 Places: ["스타벅스", "맥도날드", "GS25", "강남역", "신한은행"]
   → 받아온 장소 이름들 (최대 5개 표시)
```

---

### 3단계: 에러 로그 해석

#### ❌ 에러 1: 위치 정보 없음
```
(아무 로그도 안 나옴)
```
**원인**: 위치 권한이 거부되었거나 시뮬레이터에 위치 설정이 안 됨

**해결**:
1. 시뮬레이터: Xcode > Debug > Simulate Location > Seoul, South Korea
2. 실제 기기: 설정 > 개인정보 보호 > 위치 서비스 > DigitalCane > "앱 사용 중" 선택

---

#### ❌ 에러 2: API 키 문제
```
⚠️ Error: GOOGLE_MAPS_API_KEY not found in Secrets.plist
Projects API Status Code: 403
Error Body: { "error": { "code": 403, "message": "API key not valid" } }
```

**원인**: 
- Secrets.plist에 API 키가 없거나
- API 키가 잘못되었거나
- Google Cloud Console에서 Places API가 활성화되지 않음

**해결**:
1. `DigitalCane/Resources/Secrets.plist` 파일 확인
2. Google Cloud Console > APIs & Services > Enabled APIs에서 "Places API (New)" 활성화 확인
3. API 키 제한 설정 확인 (iOS 번들 ID: `kr.ac.kaist.assistiveailab.DigitalCane`)

---

#### ❌ 에러 3: 네트워크 타임아웃
```
Places Network Error: The request timed out.
네트워크 오류가 발생했습니다.
```

**원인**: 인터넷 연결 문제

**해결**: WiFi 연결 확인

---

#### ❌ 에러 4: API 응답은 받았지만 장소가 0개
```
✅ [NearbyPlaces] Received 0 places
```

**원인**:
- 선택한 위치 주변에 실제로 장소가 없음 (드묾)
- 반경이 너무 작음

**해결**:
1. 탐색 반경을 200m → 500m로 늘리기
2. 시뮬레이터 위치를 도심 지역으로 변경 (예: Seoul, Apple Park)

---

### 4단계: 더미 데이터로 UI 테스트

API 문제와 상관없이 UI와 나침반 기능이 작동하는지 확인:

#### 방법 1: 코드 직접 수정
`NearbyExploreView.swift`의 `fetchPlaces()` 함수 맨 위에 추가:
```swift
private func fetchPlaces() {
    // === 테스트용 더미 데이터 ===
    self.places = [
        Place(name: "강남역", address: "서울", types: [], 
              coordinate: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)),
        Place(name: "스타벅스", address: "강남구", types: [], 
              coordinate: CLLocationCoordinate2D(latitude: 37.5675, longitude: 126.9790)),
        Place(name: "GS25", address: "서울", types: [], 
              coordinate: CLLocationCoordinate2D(latitude: 37.5655, longitude: 126.9770))
    ]
    self.isLoading = false
    startScanning()
    print("✅ [TEST] Loaded 3 dummy places")
    return
    // === 이 아래는 실행 안 됨 (return으로 차단) ===
    
    guard let location = locationManager.currentLocation else {
        // ... 기존 코드
```

#### 방법 2: TestHelpers 파일 사용
프로젝트에 `TestHelpers_DummyData.swift` 파일이 생성되어 있으면:
```swift
private func fetchPlaces() {
    self.places = DummyPlacesData.generateTestPlaces()
    self.isLoading = false
    startScanning()
    return
    
    // 기존 코드...
}
```

#### 테스트 확인:
1. 앱 실행
2. "디지털 지팡이" 탭 진입
3. "준비됨: 3개의 장소" (또는 5개) 표시 확인
4. **실제 기기**에서 휴대폰을 좌우로 흔들면 "강남역", "스타벅스" 등 음성 재생 확인

---

### 5단계: 나침반 작동 확인 (실제 기기 필요)

> ⚠️ **중요**: 시뮬레이터는 나침반 센서가 없어 이 기능을 테스트할 수 없습니다!

#### 실제 기기에서:
1. 더미 데이터 또는 실제 API로 장소 로드 확인
2. 휴대폰을 좌우로 천천히 흔들기
3. 특정 장소 방향을 향할 때:
   - 강한 진동 발생 (Heavy Haptic)
   - 장소 이름 음성 재생 (TTS)
4. 같은 장소는 3초 간격으로만 다시 안내됨 (중복 방지)

---

## 📋 최종 체크리스트

### ☑️ 사전 준비
- [ ] Secrets.plist에 GOOGLE_MAPS_API_KEY 설정됨
- [ ] Google Cloud Console에서 Places API 활성화됨
- [ ] 위치 권한 "앱 사용 중" 허용됨
- [ ] 시뮬레이터에 위치 설정됨 (Seoul 등)

### ☑️ 로그 확인
- [ ] `📍 Location Updated` 로그 보임
- [ ] `🔍 [NearbyPlaces] Requesting` 로그 보임
- [ ] `✅ [NearbyPlaces] Received X places` 로그 보임 (X > 0)
- [ ] 에러 로그 없음

### ☑️ UI 확인
- [ ] "준비됨: X개의 장소" 표시됨
- [ ] "디지털 지팡이가 활성화되었습니다" 메시지 보임
- [ ] 레이더 애니메이션 표시됨 (노란색 원 확장)

### ☑️ 기능 확인 (실제 기기)
- [ ] 휴대폰 흔들 때 진동 발생
- [ ] 장소 이름 음성 재생
- [ ] 다른 방향으로 돌리면 다른 장소 안내

---

## 🆘 여전히 문제가 있다면

다음 정보를 수집하여 제공해주세요:

### 1. Xcode 콘솔 로그 (전체)
```
(앱 실행부터 "디지털 지팡이" 탭 진입까지의 모든 로그 복사)
```

### 2. 환경 정보
- [ ] 시뮬레이터 or 실제 기기?
- [ ] 실제 기기라면 기종은? (iPhone 13, 14 Pro 등)
- [ ] iOS 버전은?
- [ ] 네트워크 연결 상태는? (WiFi, 셀룰러, 연결 안 됨)

### 3. 설정 확인
- [ ] Xcode > Debug > Simulate Location 에서 어떤 위치 선택했나요?
- [ ] 탐색 반경은 몇 미터로 설정되어 있나요?

이 정보로 더 정확한 진단이 가능합니다!
