import SwiftUI
import AVFoundation

@main
struct DigitalCaneApp: App {
    // 앱 전체에서 공유할 상태 관리자들
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var navigationManager = NavigationManager()
    
    // 스플래시 화면 상태
    @State private var isShowingSplash = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashView()
                        .transition(AnyTransition.opacity)
                        .onAppear {
                            // 앱 실행 음성 및 효과음 (약간의 딜레이 후 실행)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                // 시작 효과음 (부드러운 알림음, 1001: MailReceived 등 활용 가능하지만 기본적으로 TTS로 충분)
                                // speechManager.speak("디지털 지팡이를 실행합니다.")
                                // 시각장애인 사용자를 위한 오디오 로고
                                
                                // 시스템 사운드 (선택적)
                                AudioServicesPlaySystemSound(1001)
                                
                                speechManager.speak("디지털 지팡이를 실행합니다.", interrupt: true)
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
