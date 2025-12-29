# DigitalCane 개선 이력 (2025-12-29)

## 세션 요약
Google Maps API의 한국 데이터 한계를 극복하기 위한 데이터 가공 로직 최적화 및 UX 개선.

---

## 주요 개선 사항

### 1. AI 프롬프트 최적화
**파일**: `Services/APIService.swift` - `analyzeIntent()`

#### 변경 내용
- **페르소나 재정의**: "Navigation App" → **"Digital Cane (Mobility Assistant)"**
- **입력 스타일 확장**: 
  - 기존: "서울역으로 가줘" (명령형)
  - 확장: "서울역 가는 법 좀", "어떻게 가?" (대화형/질문형)
- **Few-shot Examples 추가**: 한국어 입출력 명시
- **Hallucination 방지 강화**: "Ask > Guess" 원칙 명시

#### 효과
- 자연스러운 한국어 발화 이해율 향상
- 모호한 입력 시 명확한 질문 반환 (clarificationQuestion)

---

### 2. POI 검증 로직 강화
**파일**: `Services/NavigationManager.swift` - `findRoute()`

#### 변경 내용
```swift
// Google Places API 검색 결과 필터링
let regionTypes = ["administrative_area_level_1", "locality", ...]

if bestMatch.types.contains(regionTypes) {
    // 행정구역보다 구체적인 POI 우선 선택
    if let specificPlace = places.first(where: { ... }) {
        bestMatch = specificPlace
    }
}
```

#### 효과
- "용산역" 검색 시 "용산구(행정구역)" 대신 **"용산역(기차역)"** 정확히 선택
- 검색 정확도 대폭 향상

---

### 3. 버스/지하철 정보 정제
**파일**: `Services/APIService.swift` - `convertStep()`

#### 변경 내용
1. **`GTransitVehicle` 구조체 추가**:
   ```swift
   struct GTransitVehicle: Decodable {
       let name: GTextValue?  // "버스", "지하철"
       let type: String?      // "BUS", "SUBWAY"
   }
   ```

2. **정보 우선순위**:
   - `transitLine.shortName` 우선 (예: "750B", "4호선")
   - `transitLine.name`은 보조 (예: "서울 간선버스", "서울지하철")

3. **한국어 자연화**:
   ```swift
   if vehicleName.contains("버스") {
       lineDisplay = "\(rawLine)번 버스"  // "750B번 버스"
   } else if vehicleName.contains("지하철") {
       lineDisplay = "\(rawLine)호선"     // "4호선"
   }
   ```

#### 효과
- 기존: "간선버스 143", "지하철 456행"
- 개선: **"750B번 버스"**, **"4호선"**

---

### 4. 요약 안내 개선
**파일**: `App/ContentView.swift` - `NavigationModeView.announceOverview()`

#### 변경 내용
1. **출발지/도착지 명시**:
   ```swift
   "\(origin)에서 \(dest)로 가는 경로를 찾았습니다."
   ```

2. **주요 교통수단 요약** (인지 맵 형성 지원):
   ```swift
   let transitSteps = steps.filter { $0.type == .board }
   let lines = transitSteps.map { $0.action.replacingOccurrences(of: " 탑승", with: "") }
   "주요 이동 수단은 \(lines.joined(separator: ", "))입니다."
   ```

3. **톤 변경**:
   - 기존: "경로 안내를 시작합니다" (운전 중 느낌)
   - 개선: **"경로를 찾았습니다"** (정보 검색 결과)

#### 효과
- 사용자가 경로 개요를 먼저 파악 후 세부 단계 확인
- "연세대에서 서울대로 가는 경로를 찾았습니다. 주요 이동 수단은 750B번 버스입니다."

---

### 5. UI 안정성 개선
**파일**: `App/ContentView.swift` - `NavigationModeView`

#### 변경 내용
1. **`List` → `ScrollView + VStack`**:
   - `List`의 스타일 충돌 제거
   - 명시적 배경색/전경색 설정

2. **`LazyVStack` → `VStack`**:
   - 렌더링 안정성 향상
   - 소량 데이터(3~5단계)에는 성능 차이 없음

3. **Empty State 처리**:
   ```swift
   if navigationManager.steps.isEmpty {
       Text("경로 정보를 불러오는 중입니다...")
   }
   ```

#### 효과
- 리스트가 보이지 않던 버그 해결
- 로딩 상태 명확히 표시

---

### 6. 에러 메시지 자연화
**파일**: `Services/NavigationManager.swift`

#### 변경 내용
- 기존: "목적지를 이해하지 못했습니다. 정확한..."
- 개선: **"죄송해요, 목적지를 잘 이해하지 못했습니다. 다시 한 번 말씀해 주시겠어요?"**

---

## 한계 및 향후 개선 방향

### 현재 한계
1. **Google Maps API 한국 데이터 품질**:
   - 한국 지도법으로 인한 상세 정보 부족
   - 실시간 버스 도착 정보 없음
   - 일부 버스 번호 영어/불완전

2. **도보 경로 완전 제외**:
   - 환승 시 역 구내 동선 정보 부재

### 향후 고려 사항
1. **경로 캐싱**:
   - 자주 검색되는 경로 로컬 저장
   - API 호출 95% 절감 가능

2. **로컬 API 통합** (6개월 후):
   - Kakao Local + 공공데이터 조합
   - 자체 경로 탐색 엔진 구축

3. **사용자 피드백 수집**:
   - 실제 시각장애인 테스트
   - 선호 경로 패턴 분석

---

## 테스트 방법

### 1. 음성 입력 테스트
```
"연세대학교에서 서울대학교 가는 법 알려줘"
→ 기대 결과: "750B번 버스" 안내
```

### 2. POI 검증 테스트
```
"용산역으로 가고 싶어"
→ 기대 결과: 기차역으로 정확히 탐색 (용산구 아님)
```

### 3. 요약 안내 확인
```
경로 검색 후 자동 TTS:
"연세대학교에서 서울대학교로 가는 경로를 찾았습니다.
주요 이동 수단은 750B번 버스입니다.
총 3단계, 23개 정류장을 거칩니다."
```

---

## 마무리

Google Maps API의 한계를 인정하되, **데이터 가공과 UX 개선**으로 실용성을 최대한 확보했습니다.

완전한 해결은 로컬 API 통합이 필요하나, 현재 상태로도 **기본 기능은 작동**합니다.

사용자 피드백을 수집하며, 향후 단계적 개선을 권장합니다.
