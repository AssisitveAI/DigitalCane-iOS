import SwiftUI
import AVFoundation

@main
struct DigitalCaneApp: App {
    // 앱 전체에서 공유할 상태 관리자들
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var navigationManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechManager)
                .environmentObject(navigationManager)
                .onAppear {
                    // 앱 시작 시 필요한 권한 요청 등을 수행
                    requestPermissions()
                }
        }
    }
    
    private func requestPermissions() {
        // 추후 구현: 마이크, 위치 권한 요청 로직 호출
        speechManager.requestPermission()
    }
}
