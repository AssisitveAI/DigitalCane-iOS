import SwiftUI
import AVFoundation
import CoreLocation

// 대중교통경로안내 모드 (리스트 형태 + 요약 안내)
struct NavigationModeView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var locationManager: LocationManager // 날씨 API 호출을 위한 위치 정보 필요
    
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
            // 처음 시작할 때만 전체 개요 안내 (중복 방지)
            // 처음 시작할 때만 전체 개요 안내 (Notification 수신으로 대체되므로 제외하지 않음, 안전장치로 유지하되 중복 안되게 주의)
            // NavigationManager가 직접 Notification을 쏘므로 여기서는 수동 호출 제거
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DidStartNavigation"))) { _ in
            announceOverview()
        }
        }
    }
    
    // 전체 경로 개요 안내 (자연스러운 문장형)
    private func announceOverview() {
        let origin = navigationManager.routeOrigin
        let dest = navigationManager.routeDestination
        let totalSteps = navigationManager.steps.count
        let totalDistance = navigationManager.totalDistance
        let totalDuration = navigationManager.totalDuration
        let totalStops = navigationManager.totalTransitStops
        
        // 대중교통 탑승 횟수 계산 (walk 제외)
        let transitCount = navigationManager.steps.filter { $0.type != .walk }.count
        
        var message = ""
        if origin != "Current Location" && !origin.isEmpty {
            message = "\(origin)에서 \(dest)까지 "
        } else {
            message = "\(dest)까지 "
        }
        
        // 경로 우선순위 반영 멘트 추가 (교통수단 + 옵션 조합)
        // 1. 교통수단 파트 ("요청하신 00 경로 중")
        var modePrefix = ""
        if let modes = navigationManager.activeTransportModes, !modes.isEmpty {
            let modeNames = modes.compactMap { mode -> String? in
                switch mode {
                case "BUS": return "버스"
                case "SUBWAY": return "지하철"
                case "TRAIN": return "기차"
                default: return nil
                }
            }.joined(separator: " 또는 ")
            
            if !modeNames.isEmpty {
                modePrefix = "요청하신 \(modeNames) 경로 중 "
            }
        }
        
        message += modePrefix
        
        // 2. 선호옵션 파트 ("00 경로로")
        if let activePref = navigationManager.activeRoutingPreference {
            if activePref == "LESS_WALKING" {
                message += "도보가 가장 적은 경로로 안내해 드릴게요. "
            } else if activePref == "FEWER_TRANSFERS" {
                message += "환승이 가장 적은 경로로 안내해 드릴게요. "
            } else {
                message += "가장 빠른 경로로 안내해 드릴게요. "
            }
        } else {
            // 기본값
            message += "가장 빠른 경로로 안내해 드릴게요. "
        }
        
        message += "약 \(totalDuration) 걸리고, 총 \(totalDistance)입니다. "
        
        if transitCount > 0 {
            message += "대중교통 \(transitCount)회 탑승"
            if totalStops > 0 {
                message += ", \(totalStops)개 정류장을 지나갑니다."
            } else {
                message += "합니다."
            }
        }
        
        // 날씨 정보 가져오기 및 안내
        if let location = locationManager.currentLocation {
            WeatherService.shared.fetchCurrentWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) { weatherInfo, _ in
                DispatchQueue.main.async {
                    if let weatherInfo = weatherInfo {
                        message += " 참고로, \(weatherInfo)"
                    }
                    speechManager.speak(message)
                }
            }
        } else {
            speechManager.speak(message)
        }
    }
}
