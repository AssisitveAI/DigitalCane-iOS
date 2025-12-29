# Product Requirements Document (PRD) - DigitalCane

## 1. 개요 (Overview)
**DigitalCane**은 시각장애인 사용자가 물리적 흰지팡이와 함께 보조적으로 사용할 수 있는 iOS 애플리케이션입니다. 스마트폰의 센서와 AI 기술을 활용하여 주변 정보를 "듣고 느끼게" 해주며, 정확한 대중교통 이용을 돕는 것을 목표로 합니다.

## 2. 목표 (Goals)
1. **공간 인지력 향상**: 보이지 않는 주변 상점, 시설 등을 소리와 진동으로 알려주어 사용자의 공간 인지 범위를 확장합니다.
2. **이동 자율성 확보**: 복잡한 대중교통(버스, 지하철, 기차) 이용 시에도 타인의 도움 없이 독립적으로 경로를 파악하고 이동할 수 있도록 합니다.
3. **심리적 안정감 제공**: 명확하고 거짓 없는(Hallucination-free) 정보 제공을 통해 사용자가 안심하고 내비게이션을 신뢰할 수 있게 합니다.

## 3. 핵심 기능 (Key Features)

### 3.1. 지능형 음성 경로 안내 (Smart Navigation)
- **자연어 목적지 검색**: "서울역으로 가줘", "여기서 부산역 가는 길 알려줘" 등 자연스러운 음성 명령을 이해합니다.
- **정밀 의도 파악 (AI Intent Analysis)**:
  - OpenAI GPT-4o 기반.
  - 출발지(Origin)와 목적지(Destination)를 구분하여 추출.
  - 불확실한 발화에 대해 임의로 장소를 추측하지 않도록 프롬프트 제어 강화 (No Guessing Policy).
- **복합 경로 엔진 (Multi-modal Routing)**:
  - Google Routes API v2 활용.
  - **지원 수단**: 버스, 지하철, **기차/고속열차(KTX/SRT)** 포함 전수단.
  - **경로 우선순위**: 기본값은 **최단 시간(Fastest)**. 설정에 따라 **도보 최소화(Safety/Less Walking)** 옵션 선택 가능.
- **대화형 안내 (Conversational Guidance)**:
  - **Step 0 (요약)**: 전체 여정의 소요 시간, 환승 횟수, 총 정류장 수를 브리핑.
  - **Step Detail**: "강남역에서 2호선을 타고(교대 방면), 역삼역에 내리세요."와 같이 구체적인 행동 지침 제공.
  - **Seamless TTS**: 요약 안내 후 딜레이 없이 자연스럽게 첫 번째 단계 안내 연결.

### 3.2. 디지털 지팡이 모드 (Nearby Exploration)
- **가상 촉각 레이더 (Virtual Haptic Radar)**:
  - 스마트폰을 지팡이처럼 좌우로 스캔(Scanning).
  - 나침반(Magnetometer) 센서를 이용해 전방 **10도(±5도)** 범위 내의 장소만 정밀 감지.
  - 대상 포착 시 **Heavy Haptic Feedback(강한 진동)** 발생.
- **자동 활성화**: 앱 실행 및 위치 수신 즉시 탐색 모드 자동 시작 (Zero-touch Start).
- **유연한 반경 설정**: 설정 탭 및 메인 UI에서 탐색 범위(20m~500m) 동기화 조절.

### 3.3. 접근성 및 편의성 (Accessibility & UX)
- **High Contrast UI**: 저시력 사용자를 위한 고대비(Yellow on Black), 큰 텍스트 인터페이스.
- **VoiceOver First**: 모든 UI 요소에 적절한 Accessibility Label/Hint 적용.
- **설정(Settings) 탭**: 경로 탐색 옵션(안전 우선 vs 시간 우선), 탐색 반경 기본값 등을 통합 관리.

## 4. 기술 아키텍처 (Technical Architecture)
- **Client**: iOS (SwiftUI, MVVM 패턴)
- **Logic**:
  - `LocationManager`: CoreLocation 기반 실시간 위치 트래킹.
  - `CompassManager`: 디바이스 헤딩(Heading) 계산 및 타겟 방위각(Bearing) 매칭.
  - `SpeechManager`: SFSpeechRecognizer(STT) 및 AVSpeechSynthesizer(TTS) 통합 관리.
- **External APIs**:
  - **OpenAI API**: 사용자 발화 의도(Intent) 파싱.
  - **Google Maps Platform**:
    - `Routes API`: 경로 산출.
    - `Places API`: 주변 장소 탐색.

## 5. 연구 및 검증 계획 (Research & Validation)
- **정확도 테스트**: AI가 모호한 한국어 발음(지명)을 얼마나 정확히 필터링하고 인식하는지 검증.
- **사용성 평가**: 실제 시각장애인 보행 환경(소음, 흔들림)에서의 햅틱 인식률 및 방향 탐색 정밀도 테스트.
- **안전성 검증**: '도보 최소화' 옵션이 실제 보행 위험(횡단보도 횟수 등)을 유의미하게 줄이는지 데이터 수집 필요.
