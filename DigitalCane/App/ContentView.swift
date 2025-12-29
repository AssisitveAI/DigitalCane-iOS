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
            NearbyExploreView()
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
            // 탭 변경 시 즉시 음성 중단
            speechManager.stopSpeaking()
        }
        .onAppear {
            // 탭바 스타일링 (고대비 & 큰 글씨)
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            
            // 폰트 크기 키우기
            let fontAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18, weight: .bold)]
            
            let itemAppearance = UITabBarItemAppearance()
            itemAppearance.selected.iconColor = .systemYellow
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemYellow].merging(fontAttributes) { (current, _) in current }
            
            itemAppearance.normal.iconColor = .gray
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray].merging(fontAttributes) { (current, _) in current }
            
            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance
            
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
                .accessibilityLabel(speechManager.isRecording ? "듣고 있습니다. 손을 떼면 전송됩니다." : "마이크 버튼. 누르고 있으면 말하기, 떼면 전송")
                .accessibilityHint("화면을 길게 누르고 말한 뒤, 손을 떼세요. VoiceOver 사용자는 두 번 탭하여 시작하고, 다시 두 번 탭하여 종료할 수도 있습니다.")
            
            // 텍스트 안내
            Text(speechManager.isRecording ? "듣고 있어요..." : "화면을 누른 상태로\n목적지를 말해주세요")
                .font(.system(size: 30, weight: .bold)) // 큰 글씨
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
            
            // 인식된 텍스트 실시간 표시
            if !speechManager.transcript.isEmpty {
                Text("인식됨: \"\(speechManager.transcript)\"")
                    .font(.title2)
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
                .font(.title2)
                .bold()
                .foregroundColor(.yellow)
                .padding(.top)
                .accessibilityAddTraits(.isHeader)
            
            // 전체 단계 리스트 (스크롤 문제 수정 및 안정성을 위해 VStack 사용)
            ScrollView {
                if navigationManager.steps.isEmpty {
                    Text("경로 정보를 불러오는 중입니다...")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(navigationManager.steps.enumerated()), id: \.offset) { index, step in
                            VStack(alignment: .leading, spacing: 8) {
                                // 단계 번호와 액션
                                Text("단계 \(index + 1): \(step.action)")
                                    .font(.headline)
                                    .foregroundColor(.yellow)
                                
                                // 상세 지시
                                Text(step.instruction)
                                    .font(.body)
                                    .foregroundColor(.white)
                                
                                // 추가 정보
                                if !step.detail.isEmpty {
                                    Text(step.detail)
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.8))
                                }
                                
                                Divider().background(Color.gray.opacity(0.5))
                            }
                            .padding()
                            .background(Color.black)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("단계 \(index + 1), \(step.action). \(step.instruction)")
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
                }
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.yellow) // 고대비 강조
                .foregroundColor(.black)
                .cornerRadius(15)
            }
            .padding()
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

// 설정 뷰 (파일 분리 시 빌드 누락 방지용 통합)
struct SettingsView: View {
    @AppStorage("preferLessWalking") private var preferLessWalking: Bool = false
    @AppStorage("defaultSearchRadius") private var searchRadius: Double = 200.0
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("경로 탐색 설정")) {
                    Toggle(isOn: $preferLessWalking) {
                        VStack(alignment: .leading) {
                            Text("안전 우선 (도보 최소화)")
                                .font(.headline)
                            Text(preferLessWalking ? "걷는 거리가 적은 경로를 우선합니다.\n(소요 시간이 더 걸릴 수 있습니다)" : "최단 시간 경로를 우선합니다.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .accessibilityHint("켜면 걷는 거리를 줄이는 경로를, 끄면 시간이 가장 적게 걸리는 경로를 찾습니다.")
                }
                
                Section(header: Text("디지털 지팡이 설정")) {
                    VStack(alignment: .leading) {
                        Text("기본 탐색 반경: \(Int(searchRadius))m")
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
                        Text("버전")
                        Spacer()
                        Text("1.0.0")
                    }
                }
            }
            .navigationTitle("설정")
        }
    }
}
