import SwiftUI
import CoreLocation
import MapKit
import AVFoundation

struct NearbyExploreView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var compassManager = CompassManager()
    @EnvironmentObject var speechManager: SpeechManager
    
    @State private var places: [Place] = []
    @State private var isLoading = false
    @AppStorage("defaultSearchRadius") private var searchRadius: Double = 200.0
    @State private var isScanningMode = false // 스캔 모드 활성화 여부
    
    // 마지막으로 안내한 장소 및 시간 (중복 안내 방지)
    @State private var lastAnnouncedPlaceId: UUID?
    @State private var lastAnnouncementTime: Date = Date()
    
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                // 상단 헤더
                Text("디지털 지팡이")
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
                        ProgressView("장소 정보를 불러오는 중입니다")
                            .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            .foregroundColor(.yellow)
                    }
                    .frame(height: 150)
                } else if isScanningMode {
                    // 스캔 모드 UI (시각적 레이더)
                    ScanningRadarView()
                        .frame(height: 180)
                        .overlay(
                            Text("휴대폰을 부채질하듯\n천천히 돌려주세요")
                                .foregroundColor(.white)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .padding(.top, 180)
                        )
                } else {
                    // 대기 모드 UI
                    VStack(spacing: 20) {
                        Image(systemName: "figure.walk.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100)
                            .foregroundColor(.gray)
                        
                        Text(places.isEmpty ? "주변에 검색된 장소가 없습니다." : "준비됨: \(places.count)개의 장소")
                            .font(.title3)
                            .foregroundColor(.white)
                            .bold()
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                }
                
                // 버튼 삭제 및 자동 활성화 안내
                if !places.isEmpty && !isLoading {
                    Text("디지털 지팡이가 활성화되었습니다.\n휴대폰을 천천히 돌려보세요.")
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
            // 화면 진입 시 자동 검색 시작
            if places.isEmpty {
                fetchPlaces()
            } else {
                // 이미 데이터가 있다면 즉시 나침반 재개
                startScanning()
            }
        }
        .onDisappear {
            stopScanning()
        }
        .onChange(of: compassManager.heading) { newHeading in
            guard isScanningMode, !places.isEmpty, let currentLocation = locationManager.currentLocation else { return }
            detectPlaceInDirection(heading: newHeading, currentLocation: currentLocation)
        }
        .onChange(of: locationManager.currentLocation) { location in
            // 위치 정보가 처음 확보되었을 때 자동으로 장소 검색 시작
            if let _ = location, places.isEmpty, !isLoading {
                fetchPlaces()
                // 위치가 확보되면 나침반도 시작 (이미 시작되어 있을 수 있지만 확실히 하기 위해)
                compassManager.start()
            }
        }
    }
    
    // 반경 조절 뷰
    var radiusControlView: some View {
        VStack {
            Text("탐색 반경: \(Int(searchRadius))m")
                .font(.title3)
                .foregroundColor(.white)
                .accessibilityHidden(true)
            
            Slider(
                value: $searchRadius,
                in: 20...500,
                step: 10,
                onEditingChanged: { editing in
                    if !editing {
                        // 슬라이드 조작이 끝났을 때 API 호출 및 자동 재시작
                        fetchPlaces()
                    }
                }
            )
            .accentColor(.yellow)
            .accessibilityLabel("탐색 반경")
            .accessibilityValue("\(Int(searchRadius)) 미터")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if searchRadius < 500 {
                        searchRadius += 10
                        fetchPlaces()
                    }
                case .decrement:
                    if searchRadius > 20 {
                        searchRadius -= 10
                        fetchPlaces()
                    }
                default: break
                }
            }
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("탐색 반경 조절, 현재 \(Int(searchRadius)) 미터")
        .accessibilityHint("위아래로 스와이프하여 조절하면 자동으로 장소를 다시 검색합니다.")
    }
    
    // Google Places API 기반 주변 장소 검색 (안정적)
    // MapKit Rate Limiting 문제로 인해 Google Places API 사용
    @State private var lastFetchTime: Date = .distantPast
    private let minimumFetchInterval: TimeInterval = 3.0 // 3초 디바운싱
    
    private func fetchPlaces() {
        guard let location = locationManager.currentLocation else {
            locationManager.requestLocation()
            return
        }
        
        // 디바운싱: 3초 이내 중복 호출 방지
        let now = Date()
        guard now.timeIntervalSince(lastFetchTime) >= minimumFetchInterval else {
            print("⏱️ Debounced: 너무 빠른 재검색 방지")
            return
        }
        lastFetchTime = now
        
        isLoading = true
        stopScanning() // 갱신 중엔 잠시 중단
        
        // Google Places API (안정적, 풍부한 POI 데이터)
        APIService.shared.fetchNearbyPlaces(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            radius: searchRadius
        ) { fetchedPlaces, errorMsg in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let fetchedPlaces = fetchedPlaces {
                    self.places = fetchedPlaces
                    
                    print("✅ [Google Places] 주변 장소 \(fetchedPlaces.count)개 검색됨")
                    if !fetchedPlaces.isEmpty {
                        print("📍 Places: \(fetchedPlaces.prefix(5).map { $0.name })")
                        
                        // 데이터 수신 즉시 자동 시작
                        self.startScanning()
                        
                        // VoiceOver 안내
                        UIAccessibility.post(notification: .announcement, argument: "디지털 지팡이 활성화. \(fetchedPlaces.count)개 장소 감지됨")
                    } else {
                        UIAccessibility.post(notification: .announcement, argument: "반경 내 장소 없음")
                    }
                }
                
                if let errorMsg = errorMsg {
                    print("❌ Fetch Error: \(errorMsg)")
                    UIAccessibility.post(notification: .announcement, argument: "주변 장소를 찾을 수 없습니다")
                }
            }
        }
    }
    
    // 스캔 모드 제어
    private func startScanning() {
        guard !isScanningMode else { return }
        isScanningMode = true
        compassManager.start()
    }
    
    private func stopScanning() {
        isScanningMode = false
        compassManager.stop()
    }
    
    // 토글 함수 삭제됨 (자동화)
    
    // 방향 감지 로직
    private func detectPlaceInDirection(heading: Double, currentLocation: CLLocation) {
        // 정밀도 향상: 시야각을 20도 -> 10도(좌우 10도)로 좁힘
        let fieldOfView = 10.0
        
        // 시야각 내에 있는 장소 중 가장 정면(각도 차이가 작은)에 있는 장소를 탐색
        let bestMatch = places.map { place -> (Place, Double) in
            let bearing = compassManager.bearing(from: currentLocation.coordinate, to: place.coordinate)
            let diff = abs(bearing - heading)
            let minDiff = min(diff, 360 - diff)
            return (place, minDiff)
        }
        .filter { $0.1 < fieldOfView }
        .min { $0.1 < $1.1 } // 최소 각도 차이 우선
        
        if let (place, _) = bestMatch {
            let now = Date()
            if place.id != lastAnnouncedPlaceId || now.timeIntervalSince(lastAnnouncementTime) > 3.0 {
                hapticGenerator.impactOccurred()
                speechManager.speak(place.name)
                
                lastAnnouncedPlaceId = place.id
                lastAnnouncementTime = now
            }
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
