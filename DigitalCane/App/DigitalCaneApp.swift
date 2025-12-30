import SwiftUI
import AVFoundation

@main
struct DigitalCaneApp: App {
    // 앱 전체에서 공유할 상태 관리자들
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var navigationManager = NavigationManager()
    
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
                            // 앱 실행 음성 및 효과음 (약간의 딜레이 후 실행)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                // 시스템 사운드 (오디오 로고 역할)
                                AudioServicesPlaySystemSound(1001)
                                speechManager.speak("디지털케인을 실행합니다.", interrupt: true)
                            }
                            
                            // 2.5초 후 메인 화면으로 전환
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    isShowingSplash = false
                                }
                            }
                        }
                } else {
                    ContentView()
                        .environmentObject(speechManager)
                        .environmentObject(navigationManager)
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

// 스플래시 뷰 정의 (파일 인식 문제 해결을 위해 여기에 포함)
struct SplashView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "figure.walk")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.yellow)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                
                Text("Digital Cane")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                
                Text("당신의 눈이 되어드릴게요")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
