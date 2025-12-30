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
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    @State private var isScanningMode = false // 스캔 모드 활성화 여부
    
    // 마지막으로 안내한 장소 및 시간 (중복 안내 방지)
    @State private var lastAnnouncedPlaceId: UUID?
    @State private var lastAnnouncementTime: Date = Date()
    
    let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                // 상단 헤더
                Text("디지털케인")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.yellow)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                
                // 현재 주소 정보 (터치 시 안내)
                Button(action: {
                    if let address = locationManager.currentAddress {
                        speechManager.speak("현재 위치는 \(address)입니다.")
                    } else {
                        speechManager.speak("현재 위치 정보를 확인 중입니다.")
                    }
                }) {
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text(locationManager.currentAddress ?? "위치 확인 중...")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        
                        Text("터치하면 주소를 안내합니다")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                .accessibilityLabel("현재 주소 확인: \(locationManager.currentAddress ?? "확인 중")")
                .accessibilityHint("탭하면 현재 위치의 주소를 음성으로 안내합니다.")
                
                // 도움 요청 센터 (긴급 공유 및 전화)
                HStack(spacing: 15) {
                    // 1. 내 위치 공유 버튼
                    Button(action: shareLocation) {
                        VStack {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.title2)
                            Text("위치 전송")
                                .font(.caption)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("내 위치 전송")
                    .accessibilityHint("현재 주소와 지도 링크를 메시지로 다른 사람에게 보냅니다.")
                    
                    // 2. 보호자 호출 버튼
                    Button(action: callGuardian) {
                        VStack {
                            Image(systemName: "phone.fill")
                                .font(.title2)
                            Text("비상 전화")
                                .font(.caption)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("보호자에게 비상 전화")
                    .accessibilityHint("설정된 번호로 즉시 전화를 겁니다.")
                }
                .padding(.horizontal)
                
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshNearbyExplore"))) { _ in
            // 탭을 다시 누를 때마다 장소 정보 수동 갱신
            if !isLoading {
                fetchPlaces()
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
    // --- 도움 요청 로직 ---
    
    private func shareLocation() {
        guard let location = locationManager.currentLocation else {
            speechManager.speak("위치 정보를 아직 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.")
            return
        }
        
        let address = locationManager.currentAddress ?? "알 수 없는 위치"
        let mapLink = "https://www.google.com/maps/search/?api=1&query=\(location.coordinate.latitude),\(location.coordinate.longitude)"
        let message = "[디지털케인 긴급 위치 알림]\n내 위치: \(address)\n지도에서 보기: \(mapLink)"
        
        let activityVC = UIActivityViewController(activityItems: [message], applicationActivities: nil)
        
        // SwiftUI에서 UIViewController 호출 (최상위 뷰 탐색)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func callGuardian() {
        if emergencyContact.isEmpty {
            speechManager.speak("설정 탭에서 먼저 비상 연락처를 등록해 주세요.")
            return
        }
        
        // 숫자만 추출
        let phoneNumber = emergencyContact.filter { "0123456789".contains($0) }
        guard let url = URL(string: "tel://\(phoneNumber)") else { return }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            speechManager.speak("전화 기능을 사용할 수 없는 기기입니다.")
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
