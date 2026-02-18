import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var currentAddress: String? // 현재 주소 (역지오코딩 결과)
    @Published var currentBuildingName: String? // 현재 있는 건물/장소 명칭
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let geocoder = CLGeocoder()

    private var lastAddressLocation: CLLocation? // 주소 변환 최적화용
    private var lastBuildingCheckLocation: CLLocation? // Overpass 건물 확인 최적화용
    
    // 정밀 상태 정보 추가
    @Published var isInsideBuilding: Bool = false // 건물 내부 여부 정밀 판별 결과

    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5.0 // 5m 이상 이동 시 업데이트
    }
    
    // 명시적 시작 요청 (앱 진입 후 호출)
    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func requestLocation() {
        manager.requestLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.currentLocation = location
        
        // 1. 주소 갱신 (10미터 단위)
        if lastAddressLocation == nil || location.distance(from: lastAddressLocation!) > 10 {
            updateAddress(for: location)
        }
        
        // 2. 정밀 건물 판별 (Overpass API - 15미터 단위)
        // 건물 내부 판별은 더 정밀해야 하므로 자주 체크할 수 있으나, API 부하 고려하여 15m로 설정
        if lastBuildingCheckLocation == nil || location.distance(from: lastBuildingCheckLocation!) > 15 {
            checkCurrentBuilding(at: location)
        }
    }
    
    private func updateAddress(for location: CLLocation) {
        // 역지오코딩 (좌표 -> 주소 변환)
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ko_KR")) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first else { return }
            
            // 1. 역지오코딩 정보에서 유효한 장소명 추출
            // CLPlacemark 문서에 따르면 'name'은 주소를 포함할 수 있으므로 신뢰하지 않음.
            // 명확한 관심 지점(POI)인 'areasOfInterest'만 Fallback 데이터로 사용.
            let areaOfInterest = placemark.areasOfInterest?.first
            let validBuildingName: String? = areaOfInterest
            
            // 필터링 로직 제거하고 areasOfInterest만 채택
            let buildingName = validBuildingName
            
            // 2. 주소 문자열 조합 (한국 주소 체계 고려)
            var addressParts: [String] = []
            if let admin = placemark.administrativeArea { addressParts.append(admin) }
            if let locality = placemark.locality { addressParts.append(locality) }
            if let subLocality = placemark.subLocality { addressParts.append(subLocality) }
            if let thoroughfare = placemark.thoroughfare { addressParts.append(thoroughfare) }
            if let subThoroughfare = placemark.subThoroughfare { addressParts.append(subThoroughfare) }
            
            // 만약 상세 주소가 없으면 name이라도 추가
            if addressParts.isEmpty, let name = placemark.name {
                addressParts.append(name)
            }
            
            // 공백으로 연결하여 저장
            let fullAddress = addressParts.joined(separator: " ")
            
            DispatchQueue.main.async {
                self.currentAddress = fullAddress
                
                // Overpass API에서 이미 POI 이름을 가져온 경우 덮어쓰지 않음 (Fallback 전용)
                // Overpass 결과가 없을 때만 역지오코딩 결과를 사용
                if self.currentBuildingName == nil || self.currentBuildingName?.isEmpty == true {
                    self.currentBuildingName = buildingName
                    
                    // areasOfInterest(캠퍼스, 공원 등)가 있으면 "내부"로 표시
                    if areaOfInterest != nil {
                        self.isInsideBuilding = true
                        print("📍 [Fallback] areasOfInterest: \(areaOfInterest ?? "nil")")
                    }
                }
                
                self.lastAddressLocation = location
            }
        }
    }
    
    // MARK: - Overpass Building Check
    private func checkCurrentBuilding(at location: CLLocation) {
        lastBuildingCheckLocation = location
        
        Task {
            do {
                let buildings = try await APIService.shared.fetchNearbyBuildings(at: location.coordinate)
                
                // Delegate logic to OverpassService
                if let matchedObject = OverpassService.shared.findBuilding(at: location.coordinate, from: buildings) {
                    print("🏢 [Precision] Matched Object: \(matchedObject.name) (\(matchedObject.type))")
                    
                    await MainActor.run {
                        self.handleBuildingMatch(matchedObject, at: location, isStrictMatch: true)
                    }
                } else {
                    print("🏢 [Overpass] Strict match failed, trying proximity fallback (15m)...")
                    
                    if let nearestObject = OverpassService.shared.findNearestBuilding(at: location.coordinate, from: buildings, maxDistance: 15.0) {
                        print("📍 [Proximity] Matched Object: \(nearestObject.name) (\(nearestObject.type))")
                        await MainActor.run {
                            self.handleBuildingMatch(nearestObject, at: location, isStrictMatch: false)
                        }
                    } else {
                        print("❌ [Overpass] No building found even with proximity check.")
                        // Do not reset currentBuildingName or isInsideBuilding (keep fallback)
                    }
                }
            } catch {
                print("Error fetching nearby buildings: \(error)")
            }
        }
    }
    
    // Helper to handle building match logic (deduplicated)
    private func handleBuildingMatch(_ matchedObject: BuildingPolygon, at location: CLLocation, isStrictMatch: Bool) {
        let overpassName = matchedObject.name
        
        if overpassName == "건물" || overpassName.isEmpty {
            print("🟡 [Hybrid] Overpass name missing, calling Google Places...")
            
            Task {
                do {
                    let googleName = try await APIService.shared.fetchNearbyPlaceName(at: location.coordinate)
                    await MainActor.run {
                        self.currentBuildingName = googleName
                        print("✅ [Hybrid] Name updated by Google: \(googleName)")
                    }
                } catch {
                    print("⚠️ [Hybrid] Google Places Fallback Failed: \(error)")
                    await MainActor.run {
                        if self.currentBuildingName == nil {
                            self.currentBuildingName = overpassName
                        }
                    }
                }
                await MainActor.run {
                    self.isInsideBuilding = isStrictMatch
                }
            }
        } else {
            self.currentBuildingName = overpassName
            self.isInsideBuilding = isStrictMatch
        }
    }

    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error: \(error.localizedDescription)")
    }
}

