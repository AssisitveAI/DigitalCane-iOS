# Research Documentation: DigitalCane - AI-Assisted Navigation for the Visually Impaired

## Abstract
본 기술 문서는 시각장애인을 위한 청각 및 촉각 기반 내비게이션 시스템인 'DigitalCane'의 핵심 기술과 연구 배경을 기술한다. 본 시스템은 LLM(Large Language Model)을 활용한 자연어 의도 파악과 정밀한 센서 퓨전 기술을 결합하여, 기존 시각 정보 의존적인 내비게이션의 한계를 극복하고자 하였다.

## 1. Introduction
시각장애인의 독립적인 보행은 삶의 질과 직결되는 문제이다. 기존 흰지팡이는 근거리 장애물 탐지에는 효과적이나, 목적지까지의 경로 안내나 주변 시설(POI) 인식에는 한계가 있다. 스마트폰 내비게이션은 시각 정보(지도)에 의존적이어서 청각만으로 복잡한 대중교통 환승이나 정확한 방향을 인지하기 어렵다. 이에 따라 우리는 AI Agent 기술과 햅틱 피드백을 융합한 보조 공학 솔루션인 DigitalCane을 제안한다.

## 2. Methodology

### 2.1. Hallucination-Free Intent Analysis with LLM
가장 큰 기술적 도전 과제는 부정확한 음성 인식 결과와 LLM의 환각(Hallucination) 현상이었다. 잘못된 목적지 안내는 사용자에게 물리적 위험을 초래할 수 있다.
- **Solution**: 우리는 'Strict Extraction' 프롬프트 엔지니어링을 적용했다. 사용자의 발화에서 목적지(Destination)와 출발지(Origin)가 명확히 특정되지 않으면, AI가 임의로 장소를 유추하는 것을 차단(Nullify)하고 "다시 말씀해주세요"라고 되묻는 안전 장치(Fail-safe)를 구현했다.

### 2.2. Precision Heading & Haptic Feedback
기존의 주변 장소 알림 서비스들은 '반경 내'에 있으면 무조건 알림을 주어 정보 과부하(Information Overload)를 일으킨다.
- **Solution**: 'Digital Cane Mode'는 사용자가 스마트폰으로 직접 가리키는 방향(**Heading ±10°**)에 있는 대상만을 필터링한다. 이는 시각장애인이 소리 나는 방향으로 고개를 돌리는 자연스러운 행동 양식(Natural UI)을 모방한 것이다.
- **Algorithm**:
  1. 기기의 `True Heading`과 목표물까지의 `Bearing` 간 델타($\Delta$) 계산.
  2. $\Delta < 10^{\circ}$ 조건 만족 시에만 `Heavy Haptic` 및 `TTS` 출력.
  3. 최소 각도(Nearest-Angle) 우선 알고리즘으로 다중 중첩 장소 중 가장 정확한 대상을 선별.

### 2.3. Multi-modal Routing Optimization
시각장애인은 환승 저항이 매우 높다. 따라서 단순 `최단 거리`가 아닌, `도보 최소화(Minimal Walking)` 또는 `단순 환승`이 중요하다.
- **Adaptive Routing**: 사용자의 상황에 따라 '안전 우선(Less Walking)'과 '시간 우선(Fastest)' 모드를 동적으로 전환할 수 있는 하이브리드 라우팅 엔진을 설계하여 Google Routes API에 파라미터를 동적으로 주입한다.

## 3. Results & Discussion
초기 테스트 결과, 10도 내외의 좁은 탐색 범위 설정이 사용자가 원하는 특정 건물을 조준(Pin-pointing)하는 데 효과적임을 확인했다. 또한, 자연어 기반의 목적지 입력은 키보드 입력이 어려운 이동 환경에서 높은 사용성을 보여주었다. 향후 연구에서는 IMU 센서를 활용한 실내 정밀 측위(Indoor Positioning) 기능의 통합이 필요하다.

## 4. Conclusion
DigitalCane은 단순한 길 찾기 앱을 넘어, 시각장애인이 공간을 능동적으로 탐색하고 인지할 수 있도록 돕는 '확장된 감각 기관'으로서의 가능성을 보여주었다.

---
**Keywords**: Accessibility, Assistive Technology, LLM, Haptics, CoreLocation, Navigation
