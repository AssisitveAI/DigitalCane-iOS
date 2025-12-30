import SwiftUI

struct ContentView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var navigationManager: NavigationManager
    // 위치 관리자 추가 (전역 혹은 최상위 뷰에서 관리)
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 디지털 지팡이 (메인)
            ZStack {
                Color.black.ignoresSafeArea()
                NearbyExploreView()
            }
            .tabItem {
                Label("디지털 지팡이", systemImage: "magnifyingglass.circle.fill")
            }
            .tag(0)
            
            // Tab 2: 경로 안내
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    if navigationManager.isNavigating {
                       NavigationModeView()
                    } else {
                       VoiceCommandModeView(onCommit: { text in
                           navigationManager.findRoute(to: text, locationManager: locationManager, onFailure: { errorMessage in
                               speechManager.speak(errorMessage)
                           })
                       })
                    }
                }
            }
            .ignoresSafeArea() // 전체 화면 채우기 (iPhone SE 등 하단 여백 방지)
            .tabItem {
                Label("경로 안내", systemImage: "bus.fill")
            }
            .tag(1)
            
            // Tab 3: 설정
            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .accentColor(.yellow)
        .onChange(of: selectedTab) { _ in
            // 탭 변경 시 즉시 음성 중단 및 햅틱 피드백
            speechManager.stopSpeaking()
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        .onAppear {
            // iOS 표준 탭바 스타일 사용 (시스템 기본 반투명 효과 및 접근성 기능 자동 지원)
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// 대기 및 음성 명령 입력 모드 (버튼을 누르고 있으면 듣기)
struct VoiceCommandModeView: View {
    @EnvironmentObject var speechManager: SpeechManager
    var onCommit: (String) -> Void
    
    // 제스처 상태 추적
    @State private var isTouching = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // 시각적 피드백 (아이콘)
            Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 150, height: 150)
                .foregroundColor(speechManager.isRecording ? .red : .yellow)
                // VoiceOver 사용자를 위한 힌트 (VoiceOver는 드래그 제스처보다 이중 탭/매직 탭 사용 권장)
                .accessibilityAddTraits(.isButton)
                .accessibilityRemoveTraits(.isImage)
                .accessibilityLabel(speechManager.isRecording ? "듣고 있습니다. 손을 떼면 전송됩니다." : "마이크 버튼. 누르고 있으면 말하기, 떼면 전송")
                .accessibilityHint("이 영역은 다이렉트 터치를 지원합니다. VoiceOver가 켜져 있어도 화면을 곧바로 길게 누르고 말한 뒤 손을 떼면 전송됩니다. 또는 두 손가락으로 두 번 탭하여(매직 탭) 시작/종료할 수도 있습니다.")
            
            // 텍스트 안내
            Text(speechManager.isRecording ? "듣고 있어요..." : "화면을 누른 상태로\n목적지를 말해주세요")
                .dynamicFont(size: 30, weight: .bold) // 동적 폰트 적용
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
            
            // 인식된 텍스트 실시간 표시
            if !speechManager.transcript.isEmpty {
                Text("인식됨: \"\(speechManager.transcript)\"")
                    .dynamicFont(size: 24) // 동적 폰트 적용
                    .foregroundColor(.yellow)
                    .padding()
                    .accessibilityLabel("인식된 내용: \(speechManager.transcript)")
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle()) // 전체 화면 터치 영역
        // Hold to Speak 제스처 (DragGesture 활용)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isTouching {
                        isTouching = true
                        startListening()
                    }
                }
                .onEnded { _ in
                    isTouching = false
                    stopListeningAndCommit()
                }
        )
        // VoiceOver 매직 탭 지원 (접근성)
        .accessibilityAction(.magicTap) {
            if speechManager.isRecording {
                stopListeningAndCommit()
            } else {
                startListening()
            }
        }
        // VoiceOver 다이렉트 터치 허용 (즉시 반응)
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
    
    private func startListening() {
        if !speechManager.isRecording {
            speechManager.startRecording()
            // 햅틱 피드백 (선택)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    private func stopListeningAndCommit() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            // 햅틱 피드백
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            
            // 텍스트가 있으면 검색 실행
            if !speechManager.transcript.isEmpty {
                // 잠시 딜레이를 주어 사용자가 자신의 말이 인식되었는지 확인하게 함
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onCommit(speechManager.transcript)
                }
            } else {
                // 인식된 내용이 없으면 안내 멘트
                speechManager.speak("목소리가 인식되지 않았습니다. 다시 시도해주세요.")
            }
        }
    }
}

// 경로 안내 모드 (환승 코칭 + TTS)
// 경로 안내 모드 (리스트 형태 + 요약 안내)
struct NavigationModeView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var speechManager: SpeechManager
    
    var body: some View {
        VStack {
            // 상단 요약 정보
            Text("경로 요약")
                .dynamicFont(size: 28, weight: .bold) // 동적 폰트
                .foregroundColor(.yellow)
                .padding(.top)
                .accessibilityAddTraits(.isHeader)
            
            // 전체 단계 리스트 (스크롤 문제 수정 및 안정성을 위해 VStack 사용)
            ScrollView {
                if navigationManager.steps.isEmpty {
                    Text("경로 정보를 불러오는 중입니다...")
                        .dynamicFont(size: 18)
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(navigationManager.steps.enumerated()), id: \.offset) { index, step in
                            VStack(alignment: .leading, spacing: 8) {
                                // 단계 번호와 액션
                                Text("단계 \(index + 1): \(step.action)")
                                    .dynamicFont(size: 20, weight: .bold) // 동적 폰트
                                    .foregroundColor(.yellow)
                                
                                // 상세 지시
                                Text(step.instruction)
                                    .dynamicFont(size: 18) // 동적 폰트
                                    .foregroundColor(.white)
                                
                                // 추가 정보
                                if !step.detail.isEmpty {
                                    Text(step.detail)
                                        .dynamicFont(size: 14) // 동적 폰트
                                        .foregroundColor(Color(white: 0.8))
                                }
                                
                                Divider().background(Color.gray.opacity(0.5))
                            }
                            .padding()
                            .background(Color.black)
                            .onTapGesture {
                                // 일반 터치(저시력/비VoiceOver) 사용자를 위한 음성 안내
                                let content = "단계 \(index + 1). \(step.instruction). \(step.detail)"
                                speechManager.speak(content)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(step.action). \(step.instruction). 단계 \(index + 1)")
                            .accessibilityHint(step.detail)
                        }
                    }
                }
            }
            .background(Color.black)
            
            // 안내 종료 및 새로운 검색 버튼
            Button(action: {
                navigationManager.stopNavigation()
            }) {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("새로운 검색 / 안내 종료")
                        .dynamicFont(size: 20, weight: .bold) // 동적 폰트
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.yellow) // 고대비 강조
                .foregroundColor(.black)
                .cornerRadius(15)
            }
            .padding()
            .padding(.bottom, 20) // 탭바/안전 영역 가림 방지 여백
            .accessibilityHint("현재 안내를 종료하고, 마이크 화면으로 돌아가 새로운 목적지를 검색합니다.")
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            announceOverview()
        }
    }
    
    // 전체 경로 개요 안내 (인지맵 형성을 위해 주요 교통수단 요약 포함)
    private func announceOverview() {
        let totalSteps = navigationManager.totalSteps
        let totalStops = navigationManager.totalTransitStops
        let origin = navigationManager.routeOrigin
        let dest = navigationManager.routeDestination
        
        // 주요 교통수단 추출 (예: "4호선, 150번 버스")
        // 사용자가 전체 여정의 '구조'를 파악할 수 있도록 돕습니다.
        let transitSteps = navigationManager.steps.filter { $0.type == StepType.board }
        var lineSummary = ""
        
        if !transitSteps.isEmpty {
            let lines = transitSteps.map { step -> String in
                // "143번 버스 탑승" -> "143번 버스"
                return step.action.replacingOccurrences(of: " 탑승", with: "")
            }
            
            // "4호선, 150번 버스" 식으로 연결
            let joinedLines = lines.joined(separator: ", ")
            lineSummary = "주요 이동 수단은 \(joinedLines)입니다."
            
        } else {
            lineSummary = "도보 중심의 경로입니다."
        }
        
        // "서울역에서 시청으로 가는 경로를 찾았습니다. 주요 이동 수단은 4호선입니다. 총 5단계..."
        // 이제 사용자는 "아, 4호선을 타고 가는구나"라고 먼저 인지할 수 있습니다.
        let overview = "\(origin)에서 \(dest)로 가는 경로를 찾았습니다. \(lineSummary) 총 \(totalSteps)단계, \(totalStops)개 정류장을 거칩니다. 화면을 터치하여 상세 내용을 확인해 보세요."
        
        speechManager.speak(overview)
    }
}

struct FontScaleModifier: ViewModifier {
    @AppStorage("fontScale") var fontScale: Double = 1.0
    var size: CGFloat
    var weight: Font.Weight
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: size * fontScale, weight: weight))
    }
}

extension View {
    func dynamicFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        self.modifier(FontScaleModifier(size: size, weight: weight))
    }
}

// 설정 뷰 (파일 분리 시 빌드 누락 방지용 통합)
struct SettingsView: View {
    @AppStorage("preferLessWalking") private var preferLessWalking: Bool = false
    @AppStorage("defaultSearchRadius") private var searchRadius: Double = 200.0
    @AppStorage("fontScale") private var fontScale: Double = 1.0
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("화면 설정")) {
                    VStack(alignment: .leading) {
                        Text("글자 크기: \(String(format: "%.1f", fontScale))배")
                            .dynamicFont(size: 18, weight: .bold)
                        
                        Slider(value: $fontScale, in: 0.8...2.0, step: 0.1)
                            .accentColor(.yellow)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("글자 크기 조절")
                    .accessibilityValue("\(Int(fontScale * 100))퍼센트")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if fontScale < 2.0 { fontScale += 0.1 }
                        case .decrement:
                            if fontScale > 0.8 { fontScale -= 0.1 }
                        default: break
                        }
                    }
                }
                
                Section(header: Text("경로 탐색 설정")) {
                    Toggle(isOn: $preferLessWalking) {
                        VStack(alignment: .leading) {
                            Text("안전 우선 (도보 최소화)")
                                .dynamicFont(size: 18, weight: .bold)
                            Text(preferLessWalking ? "걷는 거리가 적은 경로를 우선합니다.\n(소요 시간이 더 걸릴 수 있습니다)" : "최단 시간 경로를 우선합니다.")
                                .dynamicFont(size: 14)
                                .foregroundColor(.gray)
                        }
                    }
                    .accessibilityHint("켜면 걷는 거리를 줄이는 경로를, 끄면 시간이 가장 적게 걸리는 경로를 찾습니다.")
                }
                
                Section(header: Text("디지털 지팡이 설정")) {
                    VStack(alignment: .leading) {
                        Text("기본 탐색 반경: \(Int(searchRadius))m")
                            .dynamicFont(size: 18)
                        Slider(value: $searchRadius, in: 20...500, step: 10)
                            .accentColor(.yellow)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("탐색 반경 설정")
                    .accessibilityValue("\(Int(searchRadius)) 미터")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if searchRadius < 500 { searchRadius += 10 }
                        case .decrement:
                            if searchRadius > 20 { searchRadius -= 10 }
                        default: break
                        }
                    }
                }
                
                Section(header: Text("앱 정보")) {
                    HStack {
                        Text("버전").dynamicFont(size: 16)
                        Spacer()
                        Text("1.0.0").dynamicFont(size: 16)
                    }
                }
            }
            .navigationTitle("설정")
        }
    }
}
