import SwiftUI
import CoreLocation
import MapKit
import AVFoundation

struct NearbyExploreView: View {
    @EnvironmentObject var locationManager: LocationManager // 전역 사용
    @StateObject private var compassManager = CompassManager()
    @EnvironmentObject var speechManager: SpeechManager
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var places: [Place] = []
    @State private var isLoading = false
    @AppStorage("defaultSearchRadius") private var searchRadius: Double = 100.0 // 초기값 조정 (Auto-tuning 시작점)
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    @AppStorage("isAutoRadiusEnabled") private var isAutoRadiusEnabled: Bool = true // 자동 조절 켜기/끄기 옵션
    @State private var isVisible = false // 화면 표시 여부 추가
    @State private var isScanningMode = false // 스캔 모드 활성화 여부
    @State private var isAutoTuning = false // 자동 조절 중인지 여부
    
    // 마지막으로 안내한 장소 및 시간 (중복 안내 방지)
    @State private var lastAnnouncedPlaceId: UUID?
    @State private var lastAnnouncementTime: Date = Date()
    @State private var lastAnnouncedPlace: Place? // 현재 시야각 내에 있는 장소
    
    @State private var weatherAnnounced = false // 날씨 안내 여부
    
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    @StateObject private var hapticManager = HapticManager()
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                // 상단 헤더
                Text(NSLocalizedString("디지털케인", comment: "App Title"))
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.yellow)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                
                // 반경 설정
                radiusControlView
                    .padding(.horizontal)
                
                if isLoading {
                    VStack {
                        ProgressView(NSLocalizedString("장소 정보를 불러오고 있습니다", comment: "Loading message"))
                            .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            .foregroundColor(.yellow)
                    }
                    .frame(height: 150)
                } else if isScanningMode {
                    // 스캔 모드 UI (시각적 레이더)
                    ScanningRadarView()
                        .frame(height: 180)
                        .padding(.bottom, 20)
                } else {
                    // 대기 모드 UI
                    VStack(spacing: 20) {
                        Image(systemName: "figure.walk.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100)
                            .foregroundColor(.gray)
                        
                        Text(places.isEmpty ? NSLocalizedString("주변에 검색된 장소가 없습니다.", comment: "No places found") : String(format: NSLocalizedString("준비됨: %d개의 장소", comment: "Places count"), places.count))
                            .font(.title3)
                            .foregroundColor(.white)
                            .bold()
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                }
                // 감지된 장소 정보 표시 (시각적 피드백)
                if let place = lastAnnouncedPlace {
                    VStack(spacing: 8) {
                        Text(place.name)
                            .dynamicFont(size: 28, weight: .bold)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                        
                        Text(place.address)
                            .dynamicFont(size: 16)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(format: NSLocalizedString("현재 감지된 장소: %@. %@", comment: "Accessibility label for current place"), place.name, place.address))
                }

                
                // 버튼 삭제 및 자동 활성화 안내
                if !places.isEmpty && !isLoading {
                    Text(NSLocalizedString("주변 탐색이 활성화되었습니다.", comment: "Exploration active"))
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.yellow.opacity(0.15))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 30) // 탭바 위쪽 여백 확보
        }
        .background(Color.black)
        .onAppear {
            isVisible = true // 화면 진입
            
            // 앱/화면 진입 시 스마트 반경 모드를 항상 기본값으로 활성화 (사용자 편의성)
            // 이전에 수동으로 껐거나 반경을 변경했더라도, 다시 들어오면 자동 모드로 시작하여 최적의 경험 제공
            if !isAutoRadiusEnabled || searchRadius != 100.0 {
                isAutoRadiusEnabled = true
                searchRadius = 100.0
            }
            
            hapticManager.prepare() // 햅틱 엔진 준비
            // 화면 진입 시 자동 검색 시작
            if places.isEmpty {
                fetchPlaces()
            } else {
                // 이미 데이터가 있다면 즉시 나침반 재개
                startScanning()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshNearbyExplore"))) { _ in
            // 탭을 다시 누를 때마다 장소 정보 수동 갱신
            if !isLoading && isVisible {
                fetchPlaces()
            }
        }
        .onDisappear {
            isVisible = false // 화면 이탈
            stopScanning()
            // 탭 전환 시 완전 초기화 (찌꺼기 상태 방지)
            lastAnnouncedPlace = nil
            lastAnnouncedPlaceId = nil
            speechManager.stopSpeaking()
        }
        .onChange(of: compassManager.heading) { newHeading in
            guard isScanningMode, !places.isEmpty, let currentLocation = locationManager.currentLocation else {
                lastAnnouncedPlace = nil // 스캔 모드가 아니거나 장소가 없으면 감지된 장소 초기화
                return
            }
            detectPlaceInDirection(heading: newHeading, currentLocation: currentLocation)
        }
        .onChange(of: locationManager.currentLocation) { location in
            // 위치 정보가 처음 확보되었을 때 자동으로 장소 검색 시작
            if let _ = location, places.isEmpty, !isLoading {
                fetchPlaces()
                // 위치가 확보되면 나침반도 시작 (이미 시작되어 있을 수 있지만 확실히 하기 위해)
                startScanning()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background || newPhase == .inactive {
                print("🔋 [Battery] App moving to background. Stopping sensors.")
                stopScanning()
            } else if newPhase == .active && isVisible {
                print("🔋 [Battery] App moving to foreground. Restarting sensors.")
                startScanning()
            }
        }
    }
    
    // 반경 조절 뷰
    var radiusControlView: some View {
        VStack {
            HStack {
                Text(isAutoRadiusEnabled ? "스마트 반경: \(Int(searchRadius))m" : "탐색 반경: \(Int(searchRadius))m")
                    .font(.title3)
                    .foregroundColor(isAutoRadiusEnabled ? .green : .white)
                
                Spacer()
                
                // 자동 모드 토글 버튼
                Button(action: {
                    isAutoRadiusEnabled.toggle()
                    if isAutoRadiusEnabled {
                        // 켜는 순간 자동 조절 시도
                        fetchPlaces(forceAutoTune: true)
                    }
                }) {
                    Image(systemName: isAutoRadiusEnabled ? "bolt.badge.a.fill" : "slider.horizontal.3")
                        .foregroundColor(isAutoRadiusEnabled ? .green : .gray)
                        .font(.title2)
                }
                .accessibilityLabel(isAutoRadiusEnabled ? "스마트 반경 켜짐" : "수동 반경 모드")
                .accessibilityHint("두 번 탭하여 모드를 전환합니다.")
            }
            .accessibilityElement(children: .combine)
            
            // 슬라이더는 항상 노출 (사용자 개입 허용)
            // 단, 스마트 모드일 때는 슬라이더 비활성화 느낌보다는 "조작 시 수동 전환"되는 UX 제공
            Slider(
                value: $searchRadius,
                in: 20...500,
                step: 10,
                onEditingChanged: { editing in
                    if editing {
                        // 사용자가 슬라이더를 잡는 순간 자동 모드 해제 (수동 오버라이드)
                        if isAutoRadiusEnabled {
                            isAutoRadiusEnabled = false
                            UIAccessibility.post(notification: .announcement, argument: "수동 조절 모드로 전환됩니다.")
                        }
                    } else {
                        // 손을 뗐을 때 검색 시작
                        fetchPlaces()
                    }
                }
            )
            .accentColor(isAutoRadiusEnabled ? .green : .yellow) // 모드에 따라 색상 힌트
            
            // 스마트 모드 상태 메시지 (슬라이더 아래)
            if isAutoRadiusEnabled {
                Text(places.count > 20 ? "장소가 많아 범위를 좁혔습니다. (변경 가능)" : (places.count <= 2 && searchRadius >= 300 ? "장소가 적어 범위를 넓혔습니다. (변경 가능)" : "자동으로 조절된 범위입니다. 슬라이더로 변경 가능합니다."))
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 4)
            }
        }
        .padding()
        // 접근성 최적화: 자동 모드일 때는 슬라이더 숨김 처리
    }
    
    // Google Places API 기반 주변 장소 검색 (안정적)
    // MapKit Rate Limiting 문제로 인해 Google Places API 사용
    @State private var lastFetchTime: Date = .distantPast
    private let minimumFetchInterval: TimeInterval = 3.0 // 3초 디바운싱
    

    
    private func fetchPlaces(forceAutoTune: Bool = false) {
        guard let location = locationManager.currentLocation else {
            locationManager.requestLocation()
            return
        }
        
        // 화면이 보이지 않으면 중단 (백그라운드 실행 방지)
        guard isVisible else { return }
        
        // 디바운싱: 3초 이내 중복 호출 방지 (forceAutoTune이면 무시)
        let now = Date()
        guard forceAutoTune || now.timeIntervalSince(lastFetchTime) >= minimumFetchInterval else {
            print("⏱️ Debounced: 너무 빠른 재검색 방지")
            return
        }
        lastFetchTime = now
        
        
        isLoading = true
        stopScanning() // 갱신 중엔 잠시 중단
        
        Task {
            // 1. 날씨 정보 가져오기 (세션 당 1회)
            if !weatherAnnounced {
                await fetchWeatherInfo(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
            
            do {
                let fetchedPlaces = try await APIService.shared.fetchNearbyPlaces(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    radius: searchRadius
                )
                
                await MainActor.run {
                    self.isLoading = false
                    
                    // 비동기 작업 완료 시점에 화면이 떠났으면 중단
                    guard self.isVisible else { return }
                    
                    // 현재 있는 건물(장소) 제외 로직 추가
                    let currentBuilding = self.locationManager.currentBuildingName?.replacingOccurrences(of: " ", with: "") ?? ""
                    
                    let filteredPlaces = fetchedPlaces.filter { place in
                        let placeName = place.name.replacingOccurrences(of: " ", with: "")
                        
                        // 1. 이름이 완전히 같거나 포함되는 경우 제외
                        if !currentBuilding.isEmpty && (placeName.contains(currentBuilding) || currentBuilding.contains(placeName)) {
                            print("🚫 [Filter] 현재 건물 제외: \(place.name)")
                            return false
                        }
                        
                        // 2. 거리가 지나치게 가까운(예: 5m 이내) 경우 본인 위치로 간주하여 제외 (옵션)
                        let distance = location.distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                        if distance < 5.0 {
                            print("🚫 [Filter] 너무 가까운 장소 제외(본인 위치 가능성): \(place.name) (\(Int(distance))m)")
                            return false
                        }
                        
                        return true
                    }
                    
                    self.places = filteredPlaces
                    
                    // 스마트 반경 조절 (Smart Radius Adjustment)
                    // 조건: 자동 모드 켜짐 + 로딩 중이 아님(재귀 방지) + 사용자 개입 없음
                    if self.isAutoRadiusEnabled {
                        let count = self.places.count
                        var newRadius = self.searchRadius
                        var needsRetry = false
                        
                        if count > 20 && self.searchRadius > 50 {
                            // 너무 많음 -> 좁히기 (혼잡도 감소)
                            newRadius = max(30, self.searchRadius * 0.5) // 절반으로 축소
                            needsRetry = true
                            print("📉 [Smart Radius] Too crowed (\(count) places). Reducing radius to \(Int(newRadius))m")
                        } else if count <= 2 && self.searchRadius < 300 {
                            // 너무 적음 -> 넓히기 (탐색 확장)
                            newRadius = min(500, self.searchRadius * 2.0) // 2배 확장
                            needsRetry = true
                            print("📈 [Smart Radius] Too sparse (\(count) places). Expanding radius to \(Int(newRadius))m")
                        }
                        
                        if needsRetry && !self.isAutoTuning { // 무한 루프 방지 (한 번의 사이클만 허용하거나 플래그 처리)
                            self.searchRadius = newRadius
                            self.isAutoTuning = true // 튜닝 시작
                            // 즉시 재검색 (디바운싱 무시 필요할 수 있으나, 여기선 자연스럽게 호출)
                            // 딜레이를 주어 사용자에게 "조절 중임"을 인식시킬 수도 있음
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.fetchPlaces(forceAutoTune: true)
                            }
                            return // 현재 결과는 무시하고 재검색 결과를 기다림
                        } else {
                            // 최적화 완료 or 한계 도달
                            self.isAutoTuning = false
                        }
                    }
                    
                    print("✅ [Hybrid] 주변 장소 \(filteredPlaces.count)개 검색됨 (원본: \(fetchedPlaces.count)개)")
                    if !filteredPlaces.isEmpty {
                        // 데이터 수신 즉시 자동 시작
                        self.startScanning()
                        
                        // 효과음 및 안내
                        SoundManager.shared.play(.success)
                        
                        // 멘트 차별화
                        if self.isAutoRadiusEnabled && self.isAutoTuning {
                           UIAccessibility.post(notification: .announcement, argument: "밀도에 맞춰 탐색 반경을 \(Int(self.searchRadius))미터로 조절했습니다. \(fetchedPlaces.count)개 장소 감지됨")
                        } else {
                           UIAccessibility.post(notification: .announcement, argument: "디지털케인 활성화. \(fetchedPlaces.count)개 장소 감지됨")
                        }
                    } else {
                        // 장소 없음 사운드
                        SoundManager.shared.play(.failure)
                        if self.isAutoRadiusEnabled && self.searchRadius >= 500 {
                             UIAccessibility.post(notification: .announcement, argument: "최대 반경까지 넓혔으나 장소가 없습니다.")
                        } else {
                             UIAccessibility.post(notification: .announcement, argument: "반경 내 장소 없음")
                        }
                    }
                }
            } catch {
                print("❌ Fetch Error: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    UIAccessibility.post(notification: .announcement, argument: "주변 장소를 찾을 수 없습니다")
                }
            }
        }
    }
    
    // 스캔 모드 제어
    private func startScanning() {
        guard isVisible else { return } // 화면이 보일 때만 시작
        guard !isScanningMode else { return }
        isScanningMode = true
        compassManager.start()
    }
    
    private func stopScanning() {
        isScanningMode = false
        compassManager.stop()
    }
    
    
    // 방향 감지 로직
    private func detectPlaceInDirection(heading: Double, currentLocation: CLLocation) {
        // 정밀도 향상: 시야각을 20도 -> 10도(좌우 10도)로 좁힘
        let fieldOfView = 10.0
        
        // 시야각 내 후보군 추출
        let candidates = places.compactMap { place -> (Place, Double, Double)? in
            let bearing = compassManager.bearing(from: currentLocation.coordinate, to: place.coordinate)
            let diff = abs(bearing - heading)
            let angleDiff = min(diff, 360 - diff)
            
            if angleDiff < fieldOfView {
                let distance = currentLocation.distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                return (place, angleDiff, distance)
            }
            return nil
        }
        
        // 스마트 가중치 스코어링 (Smart Weighted Scoring)
        // 목표: "가까운 곳"을 우선하되, 거리가 비슷하면 "더 정면"인 곳을 선택
        // 점수 공식: (거리 점수 * 0.7) + (각도 점수 * 0.3) -> 낮을수록 좋음 (Penalty Score)
        // 거리는 로그 스케일 등을 적용할 수도 있으나, 여기선 직관적인 미터 단위와 각도를 정규화하여 비교
        
        let bestMatch = candidates.min { (a, b) in
            // 정규화 (Normalization) - 대략적인 범위 가정
            // 거리: 0~100m 기준 (그 이상은 비슷하게 취급)
            // 각도: 0~10도 기준
            
            let distA = min(a.2, 100.0) / 100.0
            let distB = min(b.2, 100.0) / 100.0
            
            let angleA = a.1 / 10.0
            let angleB = b.1 / 10.0
            
            // 가중치 적용 (거리 70%, 각도 30%)
            let scoreA = (distA * 0.7) + (angleA * 0.3)
            let scoreB = (distB * 0.7) + (angleB * 0.3)
            
            return scoreA < scoreB
        }
        
        if let match = bestMatch {
            let place = match.0
            // 시야각 내 장소 업데이트 (UI 표시용)
            if lastAnnouncedPlace?.id != place.id {
                lastAnnouncedPlace = place
            }
            
            let now = Date()
            if place.id != lastAnnouncedPlaceId || now.timeIntervalSince(lastAnnouncementTime) > 3.0 {
                // 거리 계산
                let distance = currentLocation.distance(from: CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                
                // 1. 소리 재생 (띠링)
                SoundManager.shared.play(.finding)
                
                // 2. 촉각 나침반 (Core Haptics) - 장소 유형별 특화된 햅틱 피드백
                hapticManager.playPatternForPlace(place, distance: distance)
                
                // 3. 음성 안내
                
                // 접근성 정보가 있으면 함께 안내
                var announcement = place.name
                if place.isWheelchairAccessible {
                    announcement += ". 입구가 편리합니다."
                }
                
                speechManager.speak(announcement)
                
                lastAnnouncedPlaceId = place.id
                lastAnnouncementTime = now
            }
        } else {
            // 시야각 밖으로 벗어나면, 방금 안내했던 장소 ID를 리셋합니다.
            // 이렇게 해야 사용자가 다시 그 방향을 가리켰을 때 즉시 다시 안내받을 수 있습니다. ("아까 그거 뭐였지?" 시나리오 대응)
            lastAnnouncedPlace = nil
            lastAnnouncedPlaceId = nil 
        }
    }
}

// 시각적 레이더 효과 뷰
struct ScanningRadarView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                    .scaleEffect(isAnimating ? 2 : 0)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        Animation.easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.6),
                        value: isAnimating
                    )
            }
            Image(systemName: "location.north.fill")
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundColor(.yellow)
        }
        .frame(width: 200, height: 200)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Haptic Manager (Core Haptics)
// Note: 별도 파일로 분리 시 Xcode 프로젝트 참조 문제 발생 가능성으로 인해 우선 View 파일 내에 포함
import CoreHaptics

