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
            // Tab 1: 디지털케인 (메인)
            NearbyExploreView()
                .tabItem {
                    Label("디지털케인", systemImage: "magnifyingglass.circle.fill")
                }
                .tag(0)
            
            // Tab 2: 대중교통경로안내
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
                Label("대중교통경로안내", systemImage: "bus.fill")
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
            
            // Tab 5: 도움말 (사용 가이드)
            HelpGuideView()
                .tabItem {
                    Label("도움말", systemImage: "questionmark.circle.fill")
                }
                .tag(4)
        }
        .background(Color.black.ignoresSafeArea())
        .accentColor(.yellow)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNavigationTab"))) { _ in
            selectedTab = 1
        }
        .onChange(of: selectedTab) { newTab in
            // 탭 변경 시 즉시 음성 중단 (이전 탭 찌꺼기 방지)
            speechManager.stopSpeaking()
            
            // 햅틱/사운드 피드백
            SoundManager.shared.play(.tabSelection)
            
            // 이전 탭 정리 및 새 탭 초기화
            switch newTab {
            case 0: // 디지털케인 (주변 탐색)
                navigationManager.stopNavigation() // 대중교통경로안내 중이었다면 정리
                NotificationCenter.default.post(name: NSNotification.Name("RefreshNearbyExplore"), object: nil)
                speechManager.speak("주변 탐색")
            case 1: // 대중교통경로안내
                // 탭 진입 시 항상 초기화 (사용자 요청: 매번 새로 시작)
                navigationManager.stopNavigation()
                speechManager.speak("경로 탐색")
            case 2: // 도움 요청 (SOS)
                navigationManager.stopNavigation() // 대중교통경로안내 중이었다면 정리
                NotificationCenter.default.post(name: NSNotification.Name("RefreshHelpView"), object: nil)
                speechManager.speak("도움 요청")
            case 3: // 설정
                navigationManager.stopNavigation()
                speechManager.speak("설정")
            case 4: // 도움말
                navigationManager.stopNavigation()
                speechManager.speak("도움말")
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
