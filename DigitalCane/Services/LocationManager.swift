import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var currentAddress: String? // 현재 주소 (역지오코딩 결과)
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let geocoder = CLGeocoder()
    private var lastAddressLocation: CLLocation? // 주소 변환 최적화용
    
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
        
        // 10미터 이상 이동했을 때만 주소 갱신 (API 호출 최적화 - Upstream Logic)
        if lastAddressLocation == nil || location.distance(from: lastAddressLocation!) > 10 {
            updateAddress(for: location)
        }
    }
    
    private func updateAddress(for location: CLLocation) {
        // 역지오코딩 (좌표 -> 주소 변환)
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ko_KR")) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first else { return }
            
            // 주소 문자열 조합 (한국 주소 체계 고려 - Stashed Detailed Logic)
            var addressParts: [String] = []
            if let admin = placemark.administrativeArea { addressParts.append(admin) }
            if let locality = placemark.locality { addressParts.append(locality) }
            if let subLocality = placemark.subLocality { addressParts.append(subLocality) }
            if let thoroughfare = placemark.thoroughfare { addressParts.append(thoroughfare) }
            if let subThoroughfare = placemark.subThoroughfare { addressParts.append(subThoroughfare) }
            
            // 만약 상세 주소가 없으면 name(건물명 등)이라도 추가
            if addressParts.isEmpty, let name = placemark.name {
                addressParts.append(name)
            }
            
            // 공백으로 연결하여 저장
            let fullAddress = addressParts.joined(separator: " ")
            
            DispatchQueue.main.async {
                self.currentAddress = fullAddress
                self.lastAddressLocation = location
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Error: \(error.localizedDescription)")
    }
}
