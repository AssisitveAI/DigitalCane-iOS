import Foundation
import CoreLocation

class OverpassService {
    static let shared = OverpassService()
    
    /// Checks if a coordinate is inside any of the provided building polygons
    func findBuilding(at coordinate: CLLocationCoordinate2D, from buildings: [BuildingPolygon]) -> BuildingPolygon? {
        let candidates = buildings.filter { $0.points.contains(coordinate) }
        
        // Sort: Named building > Named POI > Named Area > Generic building > etc.
        return candidates.sorted { (a, b) -> Bool in
            func getScore(_ obj: BuildingPolygon) -> Int {
                var score = 0
                switch obj.type {
                case .building: score = 0
                case .poi: score = 1
                case .area: score = 2
                }
                
                // Penalize generic or empty names (lower score is better)
                if obj.name == "건물" || obj.name.isEmpty {
                    score += 10
                }
                return score
            }
            
            return getScore(a) < getScore(b)
        }.first
    }
    
    /// Finds the nearest building within a usage threshold (maxDistance)
    func findNearestBuilding(at coordinate: CLLocationCoordinate2D, from buildings: [BuildingPolygon], maxDistance: CLLocationDistance = 15.0) -> BuildingPolygon? {
        // Calculate distance to each building's polygon processing closest first
        let nearby = buildings.compactMap { building -> (BuildingPolygon, CLLocationDistance)? in
            let dist = coordinate.distanceToPolygon(building.points)
            return dist <= maxDistance ? (building, dist) : nil
        }
        
        // Sort by name quality, distance, then by type
        return nearby.sorted { (a, b) -> Bool in
            func getScore(_ obj: BuildingPolygon) -> Int {
                var score = (obj.type == .building) ? 0 : (obj.type == .poi ? 1 : 2)
                if obj.name == "건물" || obj.name.isEmpty {
                    score += 10
                }
                return score
            }
            
            let scoreA = getScore(a.0)
            let scoreB = getScore(b.0)
            
            if scoreA != scoreB {
                return scoreA < scoreB
            }
            
            return a.1 < b.1
        }.first?.0
    }
}

// MARK: - Distance Calculation Helper
extension CLLocationCoordinate2D {
    /// Calculates the minimum distance from a point to a polygon (in meters)
    func distanceToPolygon(_ points: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard !points.isEmpty else { return .infinity }
        
        var minDistance: CLLocationDistance = .infinity
        var j = points.count - 1
        
        let p = self.toLocation() // Convert self to CLLocation for distance calc
        
        for i in 0..<points.count {
            let p1 = points[i]
            let p2 = points[j]
            
            // Calculate distance to the segment p1-p2
            let dist = p.distanceToSegment(p1: p1.toLocation(), p2: p2.toLocation())
            if dist < minDistance {
                minDistance = dist
            }
            j = i
        }
        
        return minDistance
    }
    
    func toLocation() -> CLLocation {
        return CLLocation(latitude: self.latitude, longitude: self.longitude)
    }
}

extension CLLocation {
    /// Distance from point to line segment (p1, p2)
    func distanceToSegment(p1: CLLocation, p2: CLLocation) -> CLLocationDistance {
        let p = self
        
        // Planar approximation for short distances (valid for building footprint scale):
        let degreesToRadians = Double.pi / 180.0
        let lat1 = p1.coordinate.latitude * degreesToRadians
        let lon1 = p1.coordinate.longitude * degreesToRadians
        let lat2 = p2.coordinate.latitude * degreesToRadians
        let lon2 = p2.coordinate.longitude * degreesToRadians
        let lat = p.coordinate.latitude * degreesToRadians
        let lon = p.coordinate.longitude * degreesToRadians
        
        // Equirectangular approximation
        let x = (lon - lon1) * cos((lat + lat1) / 2)
        let y = lat - lat1
        
        let dx = (lon2 - lon1) * cos((lat2 + lat1) / 2)
        let dy = lat2 - lat1
        
        let dot = x * dx + y * dy
        let len_sq = dx * dx + dy * dy
        
        let param = (len_sq != 0) ? dot / len_sq : -1
        
        var xx: Double, yy: Double
        
        if param < 0 {
            xx = 0
            yy = 0
        } else if param > 1 {
            xx = dx
            yy = dy
        } else {
            xx = dx * param
            yy = dy * param
        }
        
        let dx_res = x - xx
        let dy_res = y - yy
        
        // Convert back to meters (approx R = 6371km)
        let R = 6371000.0
        return sqrt(dx_res * dx_res + dy_res * dy_res) * R
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
