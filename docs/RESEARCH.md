# Research Documentation: DigitalCane - AI-Assisted Navigation for the Visually Impaired

## Abstract
본 기술 문서는 시각장애인을 위한 청각 및 촉각 기반 내비게이션 시스템인 'DigitalCane'의 핵심 기술과 연구 배경을 기술한다. 본 시스템은 LLM(Large Language Model)을 활용한 자연어 의도 파악과 정밀한 센서 퓨전 기술을 결합하여, 기존 시각 정보 의존적인 내비게이션의 한계를 극복하고자 하였다.

## 1. Introduction
시각장애인의 독립적인 보행은 삶의 질과 직결되는 문제이다. 기존 흰지팡이는 근거리 장애물 탐지에는 효과적이나, 목적지까지의 대중교통경로안내나 주변 시설(POI) 인식에는 한계가 있다. 스마트폰 내비게이션은 시각 정보(지도)에 의존적이어서 청각만으로 복잡한 대중교통 환승이나 정확한 방향을 인지하기 어렵다. 이에 따라 우리는 AI Agent 기술과 햅틱 피드백을 융합한 보조 공학 솔루션인 DigitalCane을 제안한다.

## 2. Methodology

### 2.1. Hallucination-Free Intent Analysis with LLM
가장 큰 기술적 도전 과제는 부정확한 음성 인식 결과와 LLM의 환각(Hallucination) 현상이었다. 잘못된 목적지 안내는 사용자에게 물리적 위험을 초래할 수 있다.
- **Solution**: 우리는 'Strict Extraction' 프롬프트 엔지니어링을 적용했다. 사용자의 발화에서 목적지(Destination)와 출발지(Origin)가 명확히 특정되지 않으면, AI가 임의로 장소를 유추하는 것을 차단(Nullify)하고 "다시 말씀해주세요"라고 되묻는 안전 장치(Fail-safe)를 구현했다. 또한, 단순한 장소 인식을 넘어 **'선호 교통수단(Preference Extraction)'**까지 파악하여 개인화된 경험을 제공하도록 모델을 고도화했다.

### 2.2. Precision Heading & Haptic Feedback
기존의 주변 장소 알림 서비스들은 '반경 내'에 있으면 무조건 알림을 주어 정보 과부하(Information Overload)를 일으킨다. 또한, GPS 오차로 인해 사용자가 이미 건물 내부에 있음에도 "근처에 있습니다"라고 안내하는 부정확성이 존재했다.
- **Solution**: 
  1. **Precision Heading**: 사용자가 스마트폰으로 직접 가리키는 방향(**Heading ±10°**)에 있는 대상만을 필터링한다.
  2. **Inside-Building Detection**: **Overpass API**를 연동하여 주변 건물의 형상(Polygon) 데이터를 실시간으로 수집하고, **Ray Casting Algorithm**을 적용하여 사용자의 좌표가 건물 외곽선 내부에 있는지 수학적으로 검증한다. 이를 통해 "건물 근처"가 아닌 **"건물 내부"**임을 확신 있게 안내한다.
- **Algorithm**:
  1. **Building Geometry Fetch**: Overpass API로 반경 50m 내 건물의 Polygon 좌표 수집.
  2. **Ray Casting**: 사용자 좌표에서 가상의 반직선을 그어 다각형 변과의 교차 횟수(홀수/짝수)를 판별하여 내부 포함 여부 확인.
  3. **Heading Filter**: 건물 외부일 경우, 기기의 `True Heading`과 목표물 `Bearing` 간 델타($\Delta < 10^{\circ}$) 계산하여 시야각 내 장소만 안내.
  4. **Smart Scoring**: 다중 중첩 시 `Score = (Distance * 0.7) + (AngleOfError * 0.3)` 공식을 적용, **근거리 우선(Safety-First)** 원칙 하에 가장 적합한 대상을 선정.
  5. **Haptic Feedback**: 거리에 따라 `Core Haptics` 강도를 동적으로 조절(거리 반비례).

### 2.3. Multi-modal Routing Optimization
시각장애인은 환승 저항이 매우 높다. 따라서 단순 `최단 거리`가 아닌, `도보 최소화(Minimal Walking)` 또는 `단순 환승`이 중요하다.
- **Adaptive Routing**: 사용자의 상황에 따라 '안전 우선(Less Walking)'과 '시간 우선(Fastest)' 모드를 동적으로 전환할 수 있는 하이브리드 라우팅 엔진을 설계하여 Google Routes API에 파라미터를 동적으로 주입한다.
- **Intent-Based Routing Arbitration (의도 기반 경로 중재)**:
  - 사용자의 자연어 발화(Intent)와 앱 내 설정값(Settings)이 상충할 때를 대비한 **3단계 우선순위 계층(Hierarchy)**을 정립했다.
    1.  **Tier 1 (최우선)**: Explicit Voice Command (유효한 `routingPreference` 값 존재 시. 빈 값이나 모호한 발화는 자동 필터링.)
    2.  **Tier 2 (차선)**: User Defaults (예: 설정 메뉴의 '도보 최소화', '환승 최소화' 값. Tier 1이 `nil`일 때만 적용.)
    3.  **Tier 3 (기본)**: Fastest Route (Traffic-Aware Default)
  - 특히 LLM이 반환할 수 있는 **'빈 문자열(Empty String)' 등의 노이즈를 엄격하게 처리(Strict Sanitization)**하여, 의도가 불분명할 경우 안전하게 사용자 설정값(Tier 2)으로 이양(Fallback)되도록 설계했다.
  - 이 알고리즘은 **Active Feedback Loop**와 결합되어, 시스템이 어떤 기준을 선택했는지(예: "도보가 가장 적은 경로로 안내합니다") 음성으로 명확히 고지하여 사용자의 멘탈 모델(Mental Model)과 시스템 상태를 일치시킨다.
- **Smart Fail-over Mechanism**: 사용자가 특정 수단(예: "버스만 타겠다")을 고집하여 유효한 경로가 없는 경우(Dead-end), 시스템이 이를 감지하고 자동으로 '최적 경로'로 전환하여 안내하는 'Soft Fallback' 알고리즘을 적용했다. 이는 사용자에게 "안내 불가"라는 부정적 경험 대신 "대안 제시"라는 긍정적 솔루션을 제공하여 서비스 신뢰도(Reliability)를 유지하는 핵심 전략이다.

## 3. Results & Discussion
초기 테스트 결과, 10도 내외의 좁은 탐색 범위 설정이 사용자가 원하는 특정 건물을 조준(Pin-pointing)하는 데 효과적임을 확인했다. 또한, 자연어 기반의 목적지 입력은 키보드 입력이 어려운 이동 환경에서 높은 사용성을 보여주었다. 향후 연구에서는 IMU 센서를 활용한 실내 정밀 측위(Indoor Positioning) 기능의 통합이 필요하다.

## 4. Conclusion
DigitalCane은 단순한 길 찾기 앱을 넘어, 시각장애인이 공간을 능동적으로 탐색하고 인지할 수 있도록 돕는 '확장된 감각 기관'으로서의 가능성을 보여주었다.

---
**Keywords**: Accessibility, Assistive Technology, LLM, Haptics, CoreLocation, Navigation
