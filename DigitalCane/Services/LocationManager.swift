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
            // areasOfInterest가 있으면 우선 사용 (예: "KAIST", "서울대학교")
            let areaOfInterest = placemark.areasOfInterest?.first
            var validBuildingName: String? = areaOfInterest
            
            // 2. placemark.name 검증 (주소 정보가 이름으로 오는 경우 필터링)
            if validBuildingName == nil, let name = placemark.name {
                // 숫자만 있는 경우 ("200") 제외
                let isNumeric = CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: name.trimmingCharacters(in: .whitespaces)))
                
                // 주소 구성요소(동, 번지)와 정확히 일치하는 경우 제외
                let isAddressPart = (name == placemark.thoroughfare) || 
                                  (name == placemark.subThoroughfare) ||
                                  (name == placemark.subLocality) ||
                                  (name == placemark.locality)
                
                // "구성동 200" 처럼 동 이름이 포함된 경우 제외 (건물명이 동 이름을 포함하는 경우는 드묾, 아파트 제외)
                var isFullAddress = false
                if let thoroughfare = placemark.thoroughfare, name.contains(thoroughfare) {
                     // 단, "행정복지센터" 같은 진짜 건물명일 수도 있으므로 길이 체크 등 추가 고려 가능하나, 
                     // 보통 "OO동 123" 형태가 많으므로 안전하게 제외
                     isFullAddress = true
                }
                
                if !isNumeric && !isAddressPart && !isFullAddress {
                    validBuildingName = name
                }
            }
            
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
        
        APIService.shared.fetchNearbyBuildings(at: location.coordinate) { [weak self] buildings in
            guard let self = self else { return }
            
            // Ray Casting Algorithm으로 내 위치가 포함된 건물/영역 찾기
            // 우선순위: 구체적인 건물(.building) > 대규모 구역(.area)
            let candidates = buildings.filter { $0.points.contains(location.coordinate) }
            
            // 정렬 로직: building 우선
            let matchedObject = candidates.sorted { (a, b) -> Bool in
                // 작은 범위가 우선 (building < area)
                let aScore = (a.type == .building) ? 0 : 2
                let bScore = (b.type == .building) ? 0 : 2
                return aScore < bScore
            }.first
            
            if let matchedObject = matchedObject {
                print("🏢 [Precision] Matched Object: \(matchedObject.name) (\(matchedObject.type))")
                
                DispatchQueue.main.async {
                    // Overpass 이름이 불충분하면 Google Places로 보완
                    let overpassName = matchedObject.name
                    
                    if overpassName == "건물" || overpassName.isEmpty {
                        // 이름이 없으면 Google Places 호출
                        print("🟡 [Hybrid] Overpass name missing, calling Google Places...")
                        APIService.shared.fetchNearbyPlaceName(at: location.coordinate) { googleName in
                            DispatchQueue.main.async {
                                if let googleName = googleName {
                                    self.currentBuildingName = googleName
                                    print("✅ [Hybrid] Name updated by Google: \(googleName)")
                                } else {
                                    // Google 실패 시, Overpass "건물"은 사용하지 않고 역지오코딩(Fallback) 유지
                                    // 단, 역지오코딩 값도 없으면 어쩔 수 없이 "건물" 사용? 아니면 표시 안 함?
                                    // 표시 안 하는 게 나음 ("건물 내부"보다는 주소가 나음)
                                    if self.currentBuildingName == nil {
                                        // 역지오코딩조차 없으면 "건물" 사용
                                        self.currentBuildingName = overpassName
                                    } else {
                                        print("❌ [Hybrid] Google failed & Overpass generic. Keeping Fallback: \(self.currentBuildingName ?? "nil")")
                                    }
                                }
                            }
                        }
                    } else {
                        // Overpass 이름이 충분하면 그대로 사용
                        self.currentBuildingName = overpassName
                    }
                    
                    // 타입에 따라 컨텍스트 설정 (건물은 "내부", POI는 "바로 앞/안")
                    if matchedObject.type == .building {
                        self.isInsideBuilding = true
                    } else if matchedObject.type == .area {
                        // 대규모 구역(캠퍼스 등)도 "내부"로 간주
                        self.isInsideBuilding = true
                    } else {
                        self.isInsideBuilding = true 
                    }
                }
            } else {
                // Ray Casting 실패 -> 건물 밖이거나 데이터 없음
                // currentBuildingName은 리셋하지 않음 (역지오코딩의 areasOfInterest 유지)
                // isInsideBuilding도 유지 (역지오코딩에서 areasOfInterest가 있으면 true로 설정됨)
                print("🏢 [Overpass] No building/area matched, keeping fallback data")
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
