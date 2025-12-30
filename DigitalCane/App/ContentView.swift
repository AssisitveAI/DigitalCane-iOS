import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var navigationManager: NavigationManager
    // 위치 관리자: 전역 EnvironmentObject 사용 (싱글톤 패턴)
    @EnvironmentObject var locationManager: LocationManager
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
        TabView(selection: $selectedTab) {
            // Tab 1: 디지털 지팡이 (메인)
            NearbyExploreView()
                .tabItem {
                    Label("디지털케인", systemImage: "magnifyingglass.circle.fill")
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
                               SoundManager.shared.play(.failure)
                           })
                        })
                    }
                }
            }
            .tabItem {
                Label("경로안내", systemImage: "bus.fill")
            }
            .tag(1)
            
            // Tab 3: 도움요청 (SOS)
            HelpView()
                .tabItem {
                    Label("도움요청", systemImage: "exclamationmark.shield.fill")
                }
                .tag(2)
            
            // Tab 4: 설정
            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .background(Color.black.ignoresSafeArea())
        .accentColor(.yellow)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNavigationTab"))) { _ in
            selectedTab = 1
        }
        .onChange(of: selectedTab) { newTab in
            // 탭 변경 시 즉시 음성 중단 및 햅틱/사운드 피드백
            speechManager.stopSpeaking()
            SoundManager.shared.play(.tabSelection)
            
            // 각 탭별 기능 재실행 트리거 (Notification 발송)
            switch newTab {
            case 0: // 디지털케인 (주변 탐색)
                NotificationCenter.default.post(name: NSNotification.Name("RefreshNearbyExplore"), object: nil)
            case 1: // 경로 안내
                 // 탭 진입 시 이전 경로 정보 초기화 (새로운 검색 준비)
                 navigationManager.stopNavigation()
            case 2: // 도움 요청 (SOS)
                 NotificationCenter.default.post(name: NSNotification.Name("RefreshHelpView"), object: nil)
            default:
                break
            }
        }
        .onAppear {
            // 위치 서비스 안전 시작 (앱 진입 후)
            locationManager.start()
            
            // 탭바 스타일링 (고대비 & 큰 글씨)
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            
            let itemAppearance = UITabBarItemAppearance()
            itemAppearance.normal.iconColor = UIColor.gray
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
            itemAppearance.selected.iconColor = UIColor.systemYellow
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemYellow]
            
            appearance.stackedLayoutAppearance = itemAppearance
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
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
                Text(speechManager.isRecording ? "듣고 있습니다..." : "화면을 누른 채로\n목적지를 말씀해 주세요")
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
            // 햅틱/사운드 피드백 (통합됨)
            SoundManager.shared.play(.recordingStart)
        }
    }
    
    private func stopListeningAndCommit() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            // 햅틱/사운드 피드백 (통합됨)
            SoundManager.shared.play(.recordingEnd)
            
            if !speechManager.transcript.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onCommit(speechManager.transcript)
                }
            } else {
                speechManager.speak("목소리를 인식하지 못했습니다. 다시 말씀해 주세요.")
            }
        }
    }
}

// 경로 안내 모드 (리스트 형태 + 요약 안내)
struct NavigationModeView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var speechManager: SpeechManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 상단 요약 (총 시간 및 거리 포함)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .bottom) {
                    Text(navigationManager.routeDestination)
                        .dynamicFont(size: 28, weight: .bold)
                        .foregroundColor(.yellow)
                    
                    Spacer()
                    
                    Text(navigationManager.currentRouteDescription)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(8)
                }
                
                Text(navigationManager.routeOrigin + " 출발")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 15)
            .background(Color.white.opacity(0.03))
            
            // 단계별 안내 리스트 (인지지도 형성에 최적화된 리스트 방식)
            ScrollView {
                if navigationManager.steps.isEmpty {
                    ProgressView().tint(.yellow).padding()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(navigationManager.steps.enumerated()), id: \.offset) { index, step in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 15) {
                                    // 단계 번호 표시
                                    Text("\(index + 1)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(index == navigationManager.currentStepIndex ? .black : .yellow)
                                        .frame(width: 24, height: 24)
                                        .background(index == navigationManager.currentStepIndex ? Color.yellow : Color.clear)
                                        .overlay(Circle().stroke(Color.yellow, lineWidth: 1))
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(step.instruction)
                                            .dynamicFont(size: index == navigationManager.currentStepIndex ? 22 : 18, 
                                                        weight: index == navigationManager.currentStepIndex ? .bold : .medium)
                                            .foregroundColor(index == navigationManager.currentStepIndex ? .white : .gray)
                                        
                                        if !step.detail.isEmpty {
                                            Text(step.detail)
                                                .dynamicFont(size: 15)
                                                .foregroundColor(index == navigationManager.currentStepIndex ? .yellow.opacity(0.8) : .gray.opacity(0.6))
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: step.type == .walk ? "figure.walk" : "bus.fill")
                                        .foregroundColor(index == navigationManager.currentStepIndex ? .yellow : .gray.opacity(0.5))
                                }
                                .padding()
                                .background(index == navigationManager.currentStepIndex ? Color.white.opacity(0.08) : Color.clear)
                                .onTapGesture {
                                    navigationManager.currentStepIndex = index
                                    speechManager.speak(step.instruction)
                                }
                                
                                Divider().background(Color.gray.opacity(0.5))
                            }
                            .padding()
                            .background(Color.black)
                            .onTapGesture {
                                // 일반 터치(저시력/비VoiceOver) 사용자를 위한 음성 안내
                                let content = "단계 \(index + 1). \(step.instruction). \(step.detail)"
                                SoundManager.shared.play(.click)
                                speechManager.speak(content)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("단계 \(index + 1): \(step.instruction)")
                            .accessibilityHint(step.detail)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 안내 종료 및 새로운 검색 버튼
            Button(action: {
                SoundManager.shared.play(.click)
                navigationManager.stopNavigation()
            }) {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("새로운 검색 및 안내 종료")
                        .dynamicFont(size: 20, weight: .bold) // 동적 폰트
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            SoundManager.shared.play(.success)
            announceOverview()
        }
    }
    
    // 전체 경로 개요 안내 (거리 정보 포함)
    // 전체 경로 개요 안내 (거리 및 시간 정보 포함)
    private func announceOverview() {
        let origin = navigationManager.routeOrigin
        let dest = navigationManager.routeDestination
        let totalSteps = navigationManager.steps.count
        let totalDistance = navigationManager.totalDistance
        let totalDuration = navigationManager.totalDuration // 시간 정보 추가
        
        let message = "\(origin)에서 \(dest)로 가는 경로 안내를 시작합니다. 소요 시간은 \(totalDuration), 거리는 \(totalDistance)이며 총 \(totalSteps)단계입니다. 화면을 눌러 상세 안내를 확인하세요."
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

// --- 새로운 도움요청 필드 (복원됨) ---
struct HelpView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var locationManager: LocationManager // 전역 사용
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    
    // 유연한 연락처 처리를 위한 상태 변수
    @State private var inputNumber: String = ""
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                Text("도움요청")
                    .dynamicFont(size: 34, weight: .bold)
                    .foregroundColor(.red)
                    .padding(.top, 20)
                
                // --- 연락처 직접 수정 섹션 ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("연락받을 사람 번호")
                        .dynamicFont(size: 18, weight: .bold)
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
                    Text("기본 보호자 번호가 입력되어 있습니다. 다른 사람에게 알려주려면 번호를 수정하세요.")
                        .dynamicFont(size: 14)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("연락처 입력창. 현재 \(inputNumber) 입력됨.")
                .accessibilityHint("방문할 곳의 사람 번호를 직접 입력할 수 있습니다.")

                Divider().background(Color.gray.opacity(0.3)).padding(.horizontal)

                // 1. 현재 주소 확인
                Button(action: {
                    SoundManager.shared.play(.click)
                    if let address = locationManager.currentAddress {
                        speechManager.speak("현재 위치는 \(address)입니다.")
                    } else {
                        speechManager.speak("현재 위치 정보를 확인하고 있습니다.")
                    }
                }) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text(locationManager.currentAddress ?? "위치 확인 중...")
                            .dynamicFont(size: 20, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)

                // 2. SMS 전송
                Button(action: {
                    SoundManager.shared.play(.click)
                    shareLocation()
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("보호자에게 SMS 전송")
                            .dynamicFont(size: 20, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)

                // 3. 비상 전화
                Button(action: {
                    SoundManager.shared.play(.click)
                    callGuardian()
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("보호자에게 전화")
                            .dynamicFont(size: 20, weight: .bold)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshHelpView"))) { _ in
             // 탭 진입 시 현재 위치 안내
             if let address = locationManager.currentAddress {
                 speechManager.speak("현재 위치는 \(address)입니다.")
             } else {
                 speechManager.speak("위치 정보를 가져오는 중입니다.")
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
        if let encodedBody = message.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics),
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
