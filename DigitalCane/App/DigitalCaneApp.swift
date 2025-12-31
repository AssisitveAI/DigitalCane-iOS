import SwiftUI
import AVFoundation

@main
struct DigitalCaneApp: App {
    // 앱 전체에서 공유할 상태 관리자들
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var locationManager = LocationManager() // 위치 관리자 전역화
    
    // 스플래시 화면 상태
    @State private var isShowingSplash = true
    
    init() {
        // 앱 시작 시 전역 UI 스타일 설정 (탭바 등)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.shadowColor = nil // 그림자 제거 (깔끔한 경계)
        
        // 아이콘 및 텍스트 색상
        let normalColor = UIColor.gray
        let selectedColor = UIColor.systemYellow
        
        appearance.stackedLayoutAppearance.normal.iconColor = normalColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        
        // 모든 상태에 대해 동일하게 적용
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        // 레거시 속성 강제 적용 (불투명 보장)
        UITabBar.appearance().isTranslucent = false
        
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashView()
                        .transition(AnyTransition.opacity)
                        .onAppear {
                            // 앱 실행 음성 안내 (경고 포함)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                // 시스템 사운드 (오디오 로고 역할)
                                AudioServicesPlaySystemSound(1001)
                                
                                // 시작 안내 + 경고 메시지
                                let welcomeMessage = """
                                디지털케인을 실행합니다. 
                                안내 정보는 실제와 다를 수 있으니, 주변 상황을 함께 확인해 주세요.
                                """
                                speechManager.speak(welcomeMessage, interrupt: true)
                            }
                            
                            // 2초 후 메인 화면 전환 (경고 메시지 들을 시간 확보)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isShowingSplash = false
                                }
                            }
                        }
                } else {
                    ContentView()
                        .environmentObject(speechManager)
                        .environmentObject(navigationManager)
                        .environmentObject(locationManager) // 전역 위치 관리자 주입
                        .onAppear {
                            // 앱 시작 시 필요한 권한 요청 등을 수행
                            requestPermissions()
                        }
                }
            }
        }
    }
    
    private func requestPermissions() {
        // 추후 구현: 마이크, 위치 권한 요청 로직 호출
        speechManager.requestPermission()
    }
}


