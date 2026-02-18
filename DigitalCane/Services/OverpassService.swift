import Foundation
import CoreLocation

class OverpassService {
    static let shared = OverpassService()
    
    /// Checks if a coordinate is inside any of the provided building polygons
    func findBuilding(at coordinate: CLLocationCoordinate2D, from buildings: [BuildingPolygon]) -> BuildingPolygon? {
        let candidates = buildings.filter { $0.points.contains(coordinate) }
        
        // Sort: building(0) < area(2) (Prefer specific buildings over generic areas)
        return candidates.sorted { (a, b) -> Bool in
            let aScore = (a.type == .building) ? 0 : 2
            let bScore = (b.type == .building) ? 0 : 2
            return aScore < bScore // Lower score is better (0 < 2)
        }.first
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
