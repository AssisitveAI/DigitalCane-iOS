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
            
            // 1. 건물명/POI 명칭 추출 (현재 있는 장소 식별용)
            let buildingName = placemark.name ?? placemark.areasOfInterest?.first
            
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
                self.currentBuildingName = buildingName
                self.lastAddressLocation = location
            }
        }
    }
    
    // MARK: - Overpass Building Check
    private func checkCurrentBuilding(at location: CLLocation) {
        lastBuildingCheckLocation = location
        
        APIService.shared.fetchNearbyBuildings(at: location.coordinate) { [weak self] buildings in
            guard let self = self else { return }
            
            // Ray Casting Algorithm으로 내 위치가 포함된 건물 찾기
            // 여러 건물이 겹칠 경우 가장 먼저 발견된 것 사용 (추후 면적 작은 순 등으로 고도화 가능)
            if let matchedBuilding = buildings.first(where: { $0.points.contains(location.coordinate) }) {
                print("🏢 [Precision] You are INSIDE: \(matchedBuilding.name)")
                
                DispatchQueue.main.async {
                    // Overpass로 확인된 "확실한 내부" 정보이므로 역지오코딩 결과보다 우선하여 덮어씀
                    // 단, 이름이 "건물" 같이 모호한 경우는 제외하고 싶을 수 있으나, 
                    // 사용자가 "어느 건물 안"인지 아는게 중요하므로 업데이트
                    self.currentBuildingName = matchedBuilding.name
                    
                    // 디버깅/안내를 위해 주소 필드에도 힌트 추가 (선택사항)
                    // self.currentAddress = "\(matchedBuilding.name) 내부" 
                }
            } else {
                // 건물 밖이면 특별한 조치 없이 기존 역지오코딩 상태 유지
                // (필요 시 "건물 밖" 상태로 리셋할 수도 있음)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error: \(error.localizedDescription)")
    }
}

// MARK: - Ray Casting Algorithm
extension Array where Element == CLLocationCoordinate2D {
    /// 해당 다각형(Polygon) 좌표 배열 내부에 점이 포함되는지 판별합니다.
    /// - Parameter coordinate: 판별할 점의 좌표
    /// - Returns: 포함 여부 (Boolean)
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        var inside = false
        var j = self.count - 1
        
        for i in 0..<self.count {
            let p1 = self[i]
            let p2 = self[j]
            
            // Ray Casting: 수평선과 다각형 변의 교차점 개수 홀짝 판별
            if (p1.longitude > coordinate.longitude) != (p2.longitude > coordinate.longitude) {
                let intersectLat = (p2.latitude - p1.latitude) * (coordinate.longitude - p1.longitude) / (p2.longitude - p1.longitude) + p1.latitude
                if coordinate.latitude < intersectLat {
                    inside = !inside
                }
            }
            j = i
        }
        
        return inside
    }
}
