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
            
            // 1. 상위 레벨 영역(대학 캠퍼스, 공원 등) 우선 추출
            // areasOfInterest가 있으면 우선 사용 (예: "KAIST", "서울대학교", "올림픽공원")
            // 없으면 placemark.name 사용 (건물명 또는 주소 일부)
            let areaOfInterest = placemark.areasOfInterest?.first
            let buildingName = areaOfInterest ?? placemark.name
            
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
                }
                
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
            if let matchedObject = buildings.first(where: { $0.points.contains(location.coordinate) }) {
                print("🏢 [Precision] Matched Object: \(matchedObject.name) (\(matchedObject.type))")
                
                DispatchQueue.main.async {
                    // Overpass 정보 우선 적용
                    self.currentBuildingName = matchedObject.name
                    
                    // 타입에 따라 컨텍스트 설정 (건물은 "내부", POI는 "바로 앞/안")
                    if matchedObject.type == .building {
                        self.isInsideBuilding = true
                    } else {
                        // POI(점)의 경우 1m 반경 내에 들어온 것이므로 '도착'으로 간주해도 무방하나, 
                        // 건물 내부라는 표현보다는 '해당 장소'에 있다는 의미로 true 유지하되, UI 표현에서 유연하게 대처
                        self.isInsideBuilding = true 
                    }
                }
            } else {
                // Ray Casting 실패 -> 건물 밖이거나 데이터 없음
                DispatchQueue.main.async {
                    self.isInsideBuilding = false
                    // POI 이름을 리셋하여 역지오코딩이 Fallback으로 동작할 수 있게 함
                    self.currentBuildingName = nil
                }
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
