# MapKit 전환 완료 (2025-12-29)

## 주요 변경 사항

### Google Maps → Apple MapKit 전환

#### 이유
1. **완전 무료**: API 키 불필요, 호출 제한 없음
2. **한국 데이터 품질**: 카카오맵 데이터 사용으로 Google보다 정확
3. **iOS 네이티브**: 시스템 라이브러리, 안정성 최고

---

## 변경된 파일

### 1. `Services/APIService.swift`
- ✅ `import MapKit` 추가
- ✅ `searchPlacesMapKit()` 함수 추가
- ✅ `fetchRouteMapKit()` 함수 추가
- ✅ `convertStepMapKit()` 함수 추가
- ⚠️ Google API 함수는 백업용으로 유지 (주석 처리 안 함)

### 2. `Services/NavigationManager.swift`
- ✅ `searchPlaces()` → `searchPlacesMapKit()` 호출 변경
- ✅ `fetchRoute()` → `fetchRouteMapKit()` 호출 변경
- ✅ 행정구역 필터링 로직 제거 (MapKit은 정확한 POI 반환)

---

## MapKit의 장점

| 항목 | Google Maps | Apple MapKit |
|------|-------------|--------------|
| 비용 | 무료 (조건부) | **완전 무료** |
| API 키 | 필요 |**불필요** |
| 한국 데이터 | ⚠️ 부실 | ✅ **카카오 데이터** |
| 버스 번호 | "간선 143" | **"143번"** (추정) |
| 장소 검색 | ⚠️ | ✅ 정확 |
| 통합성 | 외부 API | **iOS 네이티브** |

---

## MapKit의 한계

1. **정류장 수 미제공**: `stopCount` 정보 없음
2. **실시간 버스 도착 정보 없음**: 별도 공공 API 필요
3. **커스터마이징 제한**: 계단 회피, 엘리베이터만 사용 등 옵션 없음

---

## 테스트 방법

### 1. 장소 검색 테스트
```
"서울역 가는 법 알려줘"
→ MapKit으로 "서울역" 검색
→ 정확한 좌표 반환 확인
```

### 2. 경로 안내 테스트
```
"연세대에서 서울대 가는 법"
→ MapKit 대중교통 경로
→ instructions가 한국어로 제공되는지 확인
→ 예: "4호선을 타고 사당역에서 내리세요"
```

### 3. UI 표시 확인
```
NavigationModeView에서:
- action: "4호선 탑승"
- instruction: "4호선을 타고 사당역에서 내리세요"
- detail: "약 5432m 이동"
```

---

## 향후 개선 사항

1. **정류장 수 파싱**: MapKit instructions에서 "6개 역 이동" 같은 텍스트 추출
2. **실시간 정보 통합**: 서울 TOPIS API로 버스 도착 시간 추가
3. **접근성 옵션**: 별도 경로 필터링 로직 구현

---

## 롤백 방법

MapKit에 문제가 있을 경우:

### NavigationManager.swift 수정
```swift
// MapKit (최신)
APIService.shared.searchPlacesMapKit(...)
APIService.shared.fetchRouteMapKit(...)

// Google (백업)
APIService.shared.searchPlaces(...)
APIService.shared.fetchRoute(...)
```

함수 호출만 변경하면 즉시 Google로 롤백 가능.

---

## 요약

**MapKit 전환으로 얻은 것:**
- ✅ 비용 제로
- ✅ 한국 데이터 품질 향상
- ✅ API 키 관리 불필요

**trade-off:**
- ⚠️ 정류장 수 정보 없음 (큰 문제 아님)
- ⚠️ 실시간 정보 제한 (추후 공공 API 통합 가능)

**결론: 한국 사용자에게는 MapKit이 압도적으로 유리**
