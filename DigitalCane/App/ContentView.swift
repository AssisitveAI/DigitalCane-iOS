import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var navigationManager: NavigationManager
    // 위치 관리자 추가 (전역 혹은 최상위 뷰에서 관리)
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTab = 0
    
    init() {
        // Force the tab bar to be opaque and anchored at the bottom
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        
        // Standard (when docked)
        UITabBar.appearance().standardAppearance = appearance
        // ScrollEdge (when content matches bottom edge)
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        // Remove transparency and floating appearance
        UITabBar.appearance().isTranslucent = false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Content Area
            ZStack {
                switch selectedTab {
                case 0:
                    NearbyExploreView()
                case 1:
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
                case 2:
                    HelpView()
                case 3:
                    SettingsView()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Anchored Tab Bar (4 Tabs)
            HStack(spacing: 0) {
                tabButton(title: "디지털케인", icon: "magnifyingglass.circle.fill", index: 0)
                tabButton(title: "경로안내", icon: "bus.fill", index: 1)
                tabButton(title: "도움요청", icon: "exclamationmark.triangle.fill", index: 2)
                tabButton(title: "설정", icon: "gearshape.fill", index: 3)
            }
            .padding(.top, 8)
            .padding(.bottom, 10) // SE has no home indicator, keep it slim
            .background(Color.black)
            .shadow(color: .white.opacity(0.1), radius: 1, x: 0, y: -1)
        }
        .background(Color.black.ignoresSafeArea())
        .accentColor(.yellow)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNavigationTab"))) { _ in
            selectedTab = 1
        }
        .onChange(of: selectedTab) { _ in
            speechManager.stopSpeaking()
            // 탭 전환 효과음 및 진동
            AudioServicesPlaySystemSound(1103)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    // Helper view for Custom Tab Buttons
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { 
            // 탭을 누를 때마다 갱신 (특히 디지털케인 탭)
            if index == 0 {
                NotificationCenter.default.post(name: NSNotification.Name("RefreshNearbyExplore"), object: nil)
            }
            selectedTab = index 
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(selectedTab == index ? .yellow : .gray)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == index ? [.isSelected] : [])
    }
}

// 대기 및 음성 명령 입력 모드 (버튼을 누르고 있으면 듣기)
struct VoiceCommandModeView: View {
    @EnvironmentObject var speechManager: SpeechManager
    var onCommit: (String) -> Void
    
    // 제스처 상태 추적
    @State private var isTouching = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 30) {
                // 시각적 피드백 (아이콘)
                Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .foregroundColor(speechManager.isRecording ? .red : .yellow)
                    .padding(.top, 40)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityRemoveTraits(.isImage)
                    .accessibilityLabel(speechManager.isRecording ? "듣고 있습니다. 손을 떼면 전송됩니다." : "마이크 버튼. 누르고 있으면 말하기, 떼면 전송")
                
                // 텍스트 안내
                Text(speechManager.isRecording ? "듣고 있어요..." : "화면을 누른 상태로\n목적지를 말해주세요")
                    .dynamicFont(size: 28, weight: .bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // 인식된 텍스트 실시간 표시
                if navigationManager.isLoading {
                    VStack(spacing: 15) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                        Text("경로를 찾는 중입니다...")
                            .dynamicFont(size: 20, weight: .bold)
                            .foregroundColor(.yellow)
                    }
                    .padding()
                } else if !speechManager.transcript.isEmpty {
                    VStack(spacing: 10) {
                        Text("인식 중...")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\"\(speechManager.transcript)\"")
                            .dynamicFont(size: 22)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 50) 
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle()) // 이 영역을 통해 터치 제스처 감지
        .background(Color.black)
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
        VStack(spacing: 0) {
            // 상단 요약 바
            VStack(spacing: 5) {
                Text(navigationManager.routeDestination)
                    .dynamicFont(size: 24, weight: .bold)
                    .foregroundColor(.yellow)
                Text("\(navigationManager.routeOrigin)에서 출발")
                    .dynamicFont(size: 14)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white.opacity(0.05))
            
            // 전단계 리스트는 축소 가능하게 (현재 단계 강조)
            ScrollView {
                if navigationManager.steps.isEmpty {
                    ProgressView()
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(navigationManager.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 15) {
                                Circle()
                                    .fill(index == navigationManager.currentStepIndex ? Color.yellow : Color.gray)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, 5)
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(step.instruction)
                                        .dynamicFont(size: index == navigationManager.currentStepIndex ? 22 : 16, 
                                                    weight: index == navigationManager.currentStepIndex ? .bold : .regular)
                                        .foregroundColor(index == navigationManager.currentStepIndex ? .white : .gray)
                                    
                                    if !step.detail.isEmpty && index == navigationManager.currentStepIndex {
                                        Text(step.detail)
                                            .dynamicFont(size: 16)
                                            .foregroundColor(.yellow.opacity(0.8))
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(index == navigationManager.currentStepIndex ? Color.yellow.opacity(0.1) : Color.clear)
                            .onTapGesture {
                                navigationManager.currentStepIndex = index
                                speechManager.speak(step.instruction)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            
            // 하단 조작 영역
            VStack(spacing: 15) {
                // 다음 단계 대형 버튼 (핵심)
                Button(action: {
                    navigationManager.nextStep()
                    speechManager.speak(navigationManager.currentInstruction)
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title)
                        Text(navigationManager.currentStepIndex < navigationManager.steps.count - 1 ? "다음 안내 받기" : "안내 종료 (도착)")
                            .dynamicFont(size: 24, weight: .bold)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(20)
                }
                .accessibilityLabel("다음 단계 안내 버튼")
                .accessibilityHint("현재 단계 안내를 완료하고 다음 단계 지침을 듣습니다.")
                
                // 안내 종료 버튼
                Button(action: {
                    navigationManager.stopNavigation()
                }) {
                    Text("안내 중단")
                        .dynamicFont(size: 16, weight: .bold)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 10)
            }
            .padding()
            .background(Color.black)
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
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    
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
                
                Section(header: Text("비상 연락처 설정")) {
                    VStack(alignment: .leading) {
                        Text("보호자 전화번호")
                            .dynamicFont(size: 18, weight: .bold)
                        TextField("010-0000-0000", text: $emergencyContact)
                            .keyboardType(.phonePad)
                            .padding(10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .accessibilityLabel("보호자 연락처 입력창")
                    .accessibilityHint("길을 잃었을 때 바로 연결할 지인의 번호를 입력하세요.")
                }
                
                Section(header: Text("디지털케인 설정")) {
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

// --- 새로운 도움요청 필드 ---
struct HelpView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @StateObject private var locationManager = LocationManager()
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    
    // 유연한 연락처 처리를 위한 상태 변수
    @State private var inputNumber: String = ""
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                Text("도움요청")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.red)
                    .padding(.top, 20)
                
                // --- 연락처 직접 수정 섹션 ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("연락받을 사람 번호")
                        .font(.headline)
                        .foregroundColor(.yellow)
                    
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.gray)
                        TextField("직접 입력 가능 (010...)", text: $inputNumber)
                            .keyboardType(.phonePad)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    Text("기본 보호자 번호가 입력되어 있습니다.\n다른 사람에게 알려주려면 번호를 수정하세요.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("연락처 입력창. 현재 \(inputNumber) 입력됨.")
                .accessibilityHint("방문할 곳의 사람 번호를 직접 입력할 수 있습니다.")

                Divider().background(Color.gray.opacity(0.3)).padding(.horizontal)

                // 1. 현재 주소 확인
                Button(action: {
                    if let address = locationManager.currentAddress {
                        speechManager.speak("현재 위치는 \(address)입니다.")
                    } else {
                        speechManager.speak("현재 위치 정보를 확인 중입니다.")
                    }
                }) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text(locationManager.currentAddress ?? "위치 확인 중...")
                            .font(.title3)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)

                // 2. SMS 전송
                Button(action: shareLocation) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("보호자에게 SMS 전송")
                            .font(.title3)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)

                // 3. 비상 전화
                Button(action: callGuardian) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("보호자에게 전화")
                            .font(.title3)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.bottom, 50)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // 설정된 보호자 번호가 있다면 기본값으로 채워줌
            if inputNumber.isEmpty {
                inputNumber = emergencyContact
            }
        }
    }
    
    // 로직 (입력된 번호 기반으로 동작)
    private func shareLocation() {
        if inputNumber.isEmpty {
            speechManager.speak("연락받을 사람의 번호를 먼저 입력해 주세요.")
            return
        }

        guard let location = locationManager.currentLocation else {
            speechManager.speak("위치 정보를 가져올 수 없습니다.")
            return
        }
        
        let address = locationManager.currentAddress ?? "알 수 없는 위치"
        let mapLink = "https://maps.google.com/maps?q=\(location.coordinate.latitude),\(location.coordinate.longitude)"
        let message = "[디지털케인 긴급 알림]\n내 위치: \(address)\n지도: \(mapLink)"
        
        // 시스템 기본 메시지 앱 호출 (사용자에게 익숙한 환경)
        let phoneNumber = inputNumber.filter { "0123456789".contains($0) }
        if let encodedBody = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
           let url = URL(string: "sms:\(phoneNumber)&body=\(encodedBody)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // SMS 불가능한 기기일 경우 대체 공유창
                let activityVC = UIActivityViewController(activityItems: [message], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.present(activityVC, animated: true)
                }
            }
        }
    }
    
    private func callGuardian() {
        if inputNumber.isEmpty {
            speechManager.speak("연락받을 사람의 번호를 먼저 입력해 주세요.")
            return
        }
        let phoneNumber = inputNumber.filter { "0123456789".contains($0) }
        if let url = URL(string: "tel://\(phoneNumber)") {
            UIApplication.shared.open(url)
        }
    }
}
