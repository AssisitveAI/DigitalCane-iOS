# Google Maps API 롤백 (2025-12-29)

## 상황
MapKit 대중교통 경로 API가 한국에서 작동하지 않음 (MKErrorDomain error 5).

## 결정
Google Maps API로 롤백.

---

## 변경 사항

### NavigationManager.swift
- ✅ `searchPlacesMapKit()` → `searchPlaces()` 복구
- ✅ `fetchRouteMapKit()` → `fetchRoute()` 복구
- ✅ POI 필터링 로직 복구

### APIService.swift
- ⚠️ MapKit 코드는 **유지** (향후 사용 가능성 대비)
- ✅ OpenAI 프롬프트 개선 **유지**
  - "무조건 한국어로 장소명 추출" 룰 적용됨
  - Google API도 이제 한국어 장소명 받음

---

## 최종 상태

### 작동하는 것
- ✅ OpenAI: 한국어 장소명 추출
- ✅ Google Places: 장소 검색 (한국어)
- ✅ Google Routes: 대중교통 경로
- ✅ 버스/지하철 번호 추출 (shortName 우선)
- ✅ UI 안정성 (VStack)
- ✅ 요약 안내 (출발지/목적지/주요수단)

### 알려진 한계
- ⚠️ Google Maps 한국 데이터 품질 (카카오보다 낮음)
- ⚠️ 일부 버스 번호 영어/불완전
- ⚠️ 실시간 정보 없음

---

## 핵심 개선 사항 (유지됨)

### 1. OpenAI 프롬프트 (최종 버전)
```
Rule 0: **ALWAYS EXTRACT PLACE NAMES IN KOREAN**
Examples:
- "서울맹학교에서 시청" → "서울시청", "서울맹학교" ✅
- "From Yonsei to Seoul Station" → "서울역", "연세대학교" ✅
```

### 2. Google API 데이터 가공
- `shortName` 우선 사용
- 버스/지하철 타입 구분
- 한국어 포맷팅

### 3. UX 개선
- 대화형 인터페이스
- 인지맵 중심 요약
- 자연스러운 에러 메시지

---

## 테스트 확인 사항

### 성공 케이스
```
✅ "서울역에서 잠실야구장"
   OpenAI: {"destinationName": "잠실야구장", "originName": "서울역"}
   Google: 경로 찾기 성공
```

### MapKit 실패 케이스 (참고)
```
❌ MapKit Directions Error: error 5
   → iPhone 지도 앱에서는 작동하지만 API는 제한적
```

---

## 결론

**Google Maps + 한국어 강제 프롬프트**가 현재 최선의 조합입니다.

MapKit은 장소 검색은 우수하나 대중교통 경로 API가 한국에서 불안정합니다.

향후 개선 방향:
1. Google 데이터 품질 모니터링
2. 사용자 피드백 수집
3. (장기) 로컬 API 통합 재시도 (Kakao + ODsay 또는 공공데이터)
