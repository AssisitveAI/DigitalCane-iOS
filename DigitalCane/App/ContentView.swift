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
    @EnvironmentObject var navigationManager: NavigationManager
    var onCommit: (String) -> Void
    
    @State private var isTouching = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 메인 컨텐츠 영역
            VStack(spacing: 30) {
                Spacer()
                
                // 시각적 피드백 (아이콘)
                ZStack {
                    Circle()
                        .stroke(speechManager.isRecording ? Color.red.opacity(0.3) : Color.yellow.opacity(0.2), lineWidth: 2)
                        .scaleEffect(speechManager.isRecording ? 1.5 : 1.0)
                        .opacity(speechManager.isRecording ? 0 : 1)
                        .animation(speechManager.isRecording ? .easeOut(duration: 1.0).repeatForever(autoreverses: false) : .default, value: speechManager.isRecording)

                    Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .foregroundColor(speechManager.isRecording ? .red : .yellow)
                }
                .accessibilityLabel(speechManager.isRecording ? "듣고 있습니다" : "마이크 버튼")
                
                // 안내 텍스트
                Text(speechManager.isRecording ? "듣고 있어요..." : "화면을 누른 상태로\n목적지를 말씀해주세요")
                    .dynamicFont(size: 28, weight: .bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // 인식된 텍스트 및 로딩 표시
                ZStack {
                    if navigationManager.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            Text("경로 탐색 중...")
                                .dynamicFont(size: 18)
                                .foregroundColor(.yellow)
                        }
                    } else if !speechManager.transcript.isEmpty {
                        Text("\"\(speechManager.transcript)\"")
                            .dynamicFont(size: 22)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(15)
                    }
                }
                .frame(height: 120)
                .padding(.horizontal)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
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
        }
        .background(Color.black)
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
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    private func stopListeningAndCommit() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            
            if !speechManager.transcript.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onCommit(speechManager.transcript)
                }
            } else {
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
            // 상단 카드 (목적지 정보)
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(navigationManager.routeDestination)
                            .dynamicFont(size: 26, weight: .bold)
                            .foregroundColor(.yellow)
                        Text(navigationManager.routeOrigin)
                            .dynamicFont(size: 14)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    // 소요 시간 뱃지
                    Text(navigationManager.currentRouteDescription)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.1))
                        .foregroundColor(.yellow)
                        .cornerRadius(20)
                        .font(.caption.bold())
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            
            // 안내 카드 (현재 단계)
            ZStack {
                if navigationManager.steps.isEmpty {
                    ProgressView().tint(.yellow)
                } else {
                    let step = navigationManager.steps[navigationManager.currentStepIndex]
                    
                    VStack(spacing: 25) {
                        // 현재 안내 지시어
                        VStack(spacing: 15) {
                            Image(systemName: step.type == .walk ? "figure.walk" : "bus.doubledecker.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.yellow)
                            
                            Text(step.instruction)
                                .dynamicFont(size: 24, weight: .bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .dynamicFont(size: 16)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(30)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(30)
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        speechManager.speak(step.instruction)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 하단 조작 바 (세련된 다이얼로그 스타일)
            HStack(spacing: 20) {
                Button(action: {
                    navigationManager.stopNavigation()
                }) {
                    Image(systemName: "xmark")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .accessibilityLabel("안내 종료")
                
                Button(action: {
                    navigationManager.nextStep()
                    speechManager.speak(navigationManager.currentInstruction)
                }) {
                    HStack {
                        Text(navigationManager.currentStepIndex < navigationManager.steps.count - 1 ? "다음 안내" : "여정 종료")
                            .dynamicFont(size: 20, weight: .bold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .cornerRadius(30)
                }
                .accessibilityLabel(navigationManager.currentStepIndex < navigationManager.steps.count - 1 ? "다음 단계로" : "안내 종료")
            }
            .padding(20)
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            announceOverview()
        }
    }
    
    // 전체 경로 개요 안내 (핵심 정보 위주로 깔끔하게)
    private func announceOverview() {
        let origin = navigationManager.routeOrigin
        let dest = navigationManager.routeDestination
        let transitSteps = navigationManager.steps.filter { $0.type == StepType.board }
        
        var summary = ""
        if !transitSteps.isEmpty {
            let lines = transitSteps.map { $0.action.replacingOccurrences(of: " 탑승", with: "") }
            summary = "\(lines.joined(separator: ", "))을 이용하는 경로입니다."
        } else {
            summary = "도보 중심의 경로입니다."
        }
        
        let message = "\(origin)에서 \(dest)로 가는 플래닝이 준비되었습니다. \(summary) 화면을 터치하면 상세 안내를 시작합니다."
        speechManager.speak(message)
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
