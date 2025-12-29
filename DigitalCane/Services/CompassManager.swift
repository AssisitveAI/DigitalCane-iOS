import Foundation
import CoreLocation
import Combine

class CompassManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var heading: Double = 0.0
    
    override init() {
        super.init()
        locationManager.delegate = self
        // 배터리 절약을 위해 필요할 때만 시작하게 할 수도 있지만, 
        // 앱 특성상 반응성이 중요하므로 초기화 시 준비
    }
    
    func start() {
        locationManager.startUpdatingHeading()
    }
    
    func stop() {
        locationManager.stopUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        
        // 진북(trueHeading)이 유효하면 사용, 아니면 자북(magneticHeading) 사용
        // 실내에서는 GPS가 약해 True Heading이 없을 수 있음 -> 자북 우선도 고려 가능하나 일반적으로 True Heading 선호
        let targetHeading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
        
        DispatchQueue.main.async {
            self.heading = targetHeading
        }
    }
    
    // 두 좌표 사이의 방위각 계산 (도 단위 0~360)
    func bearing(from current: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = current.latitude.degreesToRadians
        let lon1 = current.longitude.degreesToRadians
        let lat2 = destination.latitude.degreesToRadians
        let lon2 = destination.longitude.degreesToRadians
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        
        var degrees = radiansBearing.radiansToDegrees
        if degrees < 0 {
            degrees += 360
        }
        return degrees
    }
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}
