import SwiftUI
import AVFoundation
import CoreLocation

// 대중교통경로안내 모드 (리스트 형태 + 요약 안내)
struct NavigationModeView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var locationManager: LocationManager // 날씨 API 호출을 위한 위치 정보 필요
    
    // Quick Win 3: 복사 완료 피드백용
    @State private var showCopiedFeedback = false
    
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
                
                let displayOrigin = navigationManager.routeOrigin == "Current Location" ? "현위치" : navigationManager.routeOrigin
                Text(displayOrigin + " 출발")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 15)
            .background(Color.white.opacity(0.03))
            // Quick Win 3: 길게 누르면 경로 정보 복사
            .onLongPressGesture {
                let displayOrigin = navigationManager.routeOrigin == "Current Location" ? "현위치" : navigationManager.routeOrigin
                let copyText = "[\(displayOrigin) → \(navigationManager.routeDestination)] \(navigationManager.currentRouteDescription)"
                UIPasteboard.general.string = copyText
                
                SoundManager.shared.play(.success)
                speechManager.speak("경로 정보가 복사되었습니다.")
                
                withAnimation {
                    showCopiedFeedback = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showCopiedFeedback = false
                    }
                }
            }
            .overlay(
                Group {
                    if showCopiedFeedback {
                        Text("복사 완료!")
                            .font(.caption)
                            .foregroundColor(.black)
                            .padding(8)
                            .background(Color.yellow)
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                }
            )
            
            // 단계별 안내 리스트 (인지지도 형성에 최적화된 리스트 방식)
            ScrollViewReader { proxy in
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
                                                .lineLimit(nil)
                                                .minimumScaleFactor(0.7)
                                                .fixedSize(horizontal: false, vertical: true)
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
                                .id(index) // 스크롤 타겟 ID 설정
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
                .onAppear {
                    // 화면 진입 시 현재 단계가 있다면 해당 위치로 스크롤
                    if navigationManager.currentStepIndex > 0 {
                        proxy.scrollTo(navigationManager.currentStepIndex, anchor: .top)
                    }
                }
                .onChange(of: navigationManager.currentStepIndex) { newIndex in
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .top)
                    }
                }
            }
            
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
            // View가 나타날 때 경로 요약 발화 (Notification 놓침 방지)
            announceOverview()
        }
        // Notification은 백업으로 유지 (다른 경로로 진입 시)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DidStartNavigation"))) { _ in
            announceOverview()
        }
    }
    
    // 전체 경로 개요 안내 (Quick Win 1: 중복 로직 제거 - NavigationManager의 메시지 사용)
    private func announceOverview() {
        // NavigationManager가 생성한 기본 메시지 사용
        let baseMessage = navigationManager.routeOverviewMessage
        
        // 방어 코드: 메시지가 비어있으면 발화하지 않음
        guard !baseMessage.isEmpty else {
            print("⚠️ announceOverview: routeOverviewMessage is empty")
            return
        }
        
        // 날씨 정보 추가 (View에서만 접근 가능한 LocationManager 사용)
        if let location = locationManager.currentLocation {
            Task {
                do {
                    let weatherInfo = try await WeatherService.shared.fetchCurrentWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    await MainActor.run {
                        let finalMessage = baseMessage + " 참고로, \(weatherInfo)"
                        speechManager.speak(finalMessage)
                    }
                } catch {
                    print("⚠️ Weather fetch failed in NavigationModeView: \(error)")
                    await MainActor.run {
                        speechManager.speak(baseMessage)
                    }
                }
            }
        } else {
            speechManager.speak(baseMessage)
        }
    }
}
