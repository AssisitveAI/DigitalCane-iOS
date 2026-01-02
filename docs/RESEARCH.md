# Research Documentation: DigitalCane - Spatial Cognition & Route Planning for the Visually Impaired

## Abstract
본 기술 문서는 시각장애인을 위한 청각 및 촉각 기반 **공간 인지 및 경로 플래닝** 시스템인 'DigitalCane'의 핵심 기술과 연구 배경을 기술한다. 본 시스템은 실시간 턴바이턴 내비게이션이 아니라, 사용자가 **이동 전에 주변 환경을 인지하고 경로를 머릿속에 그릴 수 있도록** 돕는 데 초점을 둔다. LLM(Large Language Model)을 활용한 자연어 의도 파악과 정밀한 센서 퓨전 기술을 결합하여, 기존 시각 정보 의존적인 내비게이션의 한계를 극복하고자 하였다.

## 1. Introduction
시각장애인의 독립적인 보행은 삶의 질과 직결되는 문제이다. 기존 흰지팡이는 근거리 장애물 탐지에는 효과적이나, 목적지까지의 경로 파악이나 주변 시설(POI) 인식에는 한계가 있다. 기존 스마트폰 내비게이션은 시각 정보(지도)에 의존적이고 실시간 턴바이턴에 초점을 맞춰, 청각만으로 복잡한 대중교통 환승을 **사전에 계획**하기 어렵다. 이에 따라 우리는 AI Agent 기술과 햅틱 피드백을 융합한 보조 공학 솔루션인 DigitalCane을 제안한다. 본 시스템은 실시간 길 안내가 아니라, **공간 인지지도 형성(Mental Map Formation)**과 **이동 전 경로 플래닝(Pre-trip Planning)**을 지원하는 데 초점을 둔다.

## 2. Methodology

### 2.1. Hallucination-Free Intent Analysis with LLM
가장 큰 기술적 도전 과제는 부정확한 음성 인식 결과와 LLM의 환각(Hallucination) 현상이었다. 잘못된 목적지 안내는 사용자에게 물리적 위험을 초래할 수 있다.
- **Solution**: 우리는 'Strict Extraction' 프롬프트 엔지니어링을 적용했다. 사용자의 발화에서 목적지(Destination)와 출발지(Origin)가 명확히 특정되지 않으면, AI가 임의로 장소를 유추하는 것을 차단(Nullify)하고 "다시 말씀해주세요"라고 되묻는 안전 장치(Fail-safe)를 구현했다. 또한, 단순한 장소 인식을 넘어 **'선호 교통수단(Preference Extraction)'**까지 파악하여 개인화된 경험을 제공하도록 모델을 고도화했다.

### 2.2. Precision Heading & Haptic Feedback
### 2.2. Hybrid Location Context Awareness with Tiered Fallback
기존 위치 기반 서비스의 한계는 **부정확성(Inaccuracy)**과 **정보 부재(Missing Data)**였다. GPS만으로는 실내/실외 구분이 불가능하며, OpenStreetMap(Overpass)은 건물 형상은 정확하나 명칭(Name)이 누락된 경우가 많다. 이를 해결하기 위해 우리는 **3계층 하이브리드 위치 인식 엔진**을 개발했다.

1.  **Geometric Analysis (OpenStreetMap)**:
    - **Overpass API**를 사용하여 주변 건물의 Polygon 좌표뿐만 아니라 대규모 구역(`is_in` Query: 대학 캠퍼스, 공원 등) 정보를 수집한다.
    - **Ray Casting Algorithm**을 통해 사용자가 특정 건물 또는 구역 내부에 있는지 판별하여 "근처"가 아닌 **"내부"**라는 정확한 물리적 맥락을 확보한다.

2.  **Semantic Enrichment (Google Places API)**:
    - Overpass에서 건물 형태는 찾았으나 이름이 누락된 경우(예: "building"), 즉시 **Google Places API (New)**를 호출하여 현 위치의 정확한 장소명(예: "KAIST N1")을 가져온다.
    - 이를 통해 **기하학적 정확성(OSM)**과 **의미적 정확성(Google)**을 결합한 하이브리드 정보를 제공한다.

3.  **Tiered Fallback System (계층형 안전장치)**:
    - 정보의 가용성에 따라 **5단계 Fallback** 구조를 적용하여 어떤 상황에서도 최선의 위치 정보를 제공한다.
    - **Level 1 (Best)**: 건물 내부 + 정확한 이름 (Overpass Geometry + Google Name)
    - **Level 2**: 건물 내부 (Overpass Building)
    - **Level 3**: 대규모 구역 내부 (Overpass Area - 예: "KAIST 내부")
    - **Level 4**: 관심 영역 (Apple AreasOfInterest - 예: "올림픽공원")
    - **Level 5**: 지번 주소 (Geocoder)

- **Algorithm Detail**:
  1. **Fetch**: Overpass API로 Building/Area Polygon 수집.
  2. **Check**: Ray Casting으로 내부 포함 여부 확인.
  3. **Sort**: 여러 구역 중첩 시 `Building(구체적) > Area(광역)` 순으로 우선순위 정렬.
  4. **Enrich**: 선택된 객체의 이름이 비어있으면 Google Places API로 이름 보완(Backfilling).
  5. **Feedback**: 최종 결정된 컨텍스트("OOO 내부")를 TTS로 안내.

### 2.3. Multi-modal Routing Optimization
시각장애인은 환승 저항이 매우 높다. 따라서 단순 `최단 거리`가 아닌, `도보 최소화(Minimal Walking)` 또는 `단순 환승`이 중요하다.
- **Adaptive Routing**: 사용자의 상황에 따라 '안전 우선(Less Walking)'과 '시간 우선(Fastest)' 모드를 동적으로 전환할 수 있는 하이브리드 라우팅 엔진을 설계하여 Google Routes API에 파라미터를 동적으로 주입한다.
- **Intent-Based Routing Arbitration (의도 기반 경로 중재)**:
  - 사용자의 자연어 발화(Intent)와 앱 내 설정값(Settings)이 상충할 때를 대비한 **3단계 우선순위 계층(Hierarchy)**을 정립했다.
    1.  **Tier 1 (최우선)**: Explicit Voice Command (유효한 `routingPreference` 값 존재 시. 빈 값이나 모호한 발화는 자동 필터링.)
    2.  **Tier 2 (차선)**: User Defaults (예: 설정 메뉴의 '도보 최소화', '환승 최소화' 값. Tier 1이 `nil`일 때만 적용.)
    3.  **Tier 3 (기본)**: Fastest Route (Traffic-Aware Default)
  - 특히 LLM이 반환할 수 있는 **'빈 문자열(Empty String)' 등의 노이즈를 엄격하게 처리(Strict Sanitization)**하여, 의도가 불분명할 경우 안전하게 사용자 설정값(Tier 2)으로 이양(Fallback)되도록 설계했다.
  - 이 알고리즘은 **Active Feedback Loop**와 결합되어, 시스템이 어떤 기준을 선택했는지(예: "도보가 가장 적은 경로로 안내합니다") 음성으로 명확히 고지하여 사용자의 멘탈 모델(Mental Model)과 시스템 상태를 일치시킨다. 이를 위해 **Notification 기반의 상태 동기화(State Synchronization)**를 적용, 데이터 로딩과 음성 출력 간의 미세한 타이밍 차이(Race Condition)를 원천 차단했다.
- **Smart Fail-over Mechanism**: 사용자가 특정 수단(예: "버스만 타겠다")을 고집하여 유효한 경로가 없는 경우(Dead-end), 시스템이 이를 감지하고 자동으로 '최적 경로'로 전환하여 안내하는 'Soft Fallback' 알고리즘을 적용했다. 이는 사용자에게 "안내 불가"라는 부정적 경험 대신 "대안 제시"라는 긍정적 솔루션을 제공하여 서비스 신뢰도(Reliability)를 유지하는 핵심 전략이다.

## 3. Results & Discussion
초기 테스트 결과, 10도 내외의 좁은 탐색 범위 설정이 사용자가 원하는 특정 건물을 조준(Pin-pointing)하는 데 효과적임을 확인했다. 또한, 자연어 기반의 목적지 입력은 키보드 입력이 어려운 이동 환경에서 높은 사용성을 보여주었다. 향후 연구에서는 IMU 센서를 활용한 실내 정밀 측위(Indoor Positioning) 기능의 통합이 필요하다.

## 4. Conclusion
DigitalCane은 단순한 길 찾기 앱을 넘어, 시각장애인이 공간을 능동적으로 탐색하고 인지할 수 있도록 돕는 '확장된 감각 기관'으로서의 가능성을 보여주었다.

---
**Keywords**: Accessibility, Assistive Technology, LLM, Haptics, CoreLocation, Navigation
