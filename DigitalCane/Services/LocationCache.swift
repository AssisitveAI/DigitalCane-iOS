import Foundation
import CoreLocation

/// 위치 기반 데이터를 캐싱하여 중복 API 호출을 방지하는 서비스
class LocationCache {
    static let shared = LocationCache()
    
    // NSCache를 사용하여 메모리 관리 자동화 (좌표를 String 키로 변환하여 사용)
    private let placeCache = NSCache<NSString, NSArray>()
    private let buildingCache = NSCache<NSString, NSArray>()
    
    // 캐시 유효 거리 (이 거리 내의 재검색은 캐시 사용)
    private let cacheThreshold: Double = 15.0
    
    // 마지막으로 검색한 위치 저장
    private var lastPlaceLocation: CLLocation?
    private var lastBuildingLocation: CLLocation?
    
    private init() {}
    
    /// 캐시된 장소 목록을 반환합니다.
    func getCachedPlaces(for location: CLLocation) -> [Place]? {
        guard let last = lastPlaceLocation, location.distance(from: last) < cacheThreshold else {
            return nil
        }
        
        let key = createKey(from: last.coordinate)
        return placeCache.object(forKey: key as NSString) as? [Place]
    }
    
    /// 장소 목록을 캐시에 저장합니다.
    func setCachedPlaces(_ places: [Place], for location: CLLocation) {
        let key = createKey(from: location.coordinate)
        placeCache.setObject(places as NSArray, forKey: key as NSString)
        lastPlaceLocation = location
    }
    
    /// 캐시된 건물 폴리곤 목록을 반환합니다.
    func getCachedBuildings(for location: CLLocation) -> [BuildingPolygon]? {
        guard let last = lastBuildingLocation, location.distance(from: last) < cacheThreshold else {
            return nil
        }
        
        let key = createKey(from: last.coordinate)
        return buildingCache.object(forKey: key as NSString) as? [BuildingPolygon]
    }
    
    /// 건물 폴리곤 목록을 캐시에 저장합니다.
    func setCachedBuildings(_ buildings: [BuildingPolygon], for location: CLLocation) {
        let key = createKey(from: location.coordinate)
        buildingCache.setObject(buildings as NSArray, forKey: key as NSString)
        lastBuildingLocation = location
    }
    
    /// 좌표를 캐시 키로 변환 (소수점 4자리까지 사용하여 약 11m 정밀도 유지)
    private func createKey(from coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
    }
    
    /// 모든 캐시 삭제
    func clearAll() {
        placeCache.removeAllObjects()
        buildingCache.removeAllObjects()
        lastPlaceLocation = nil
        lastBuildingLocation = nil
    }
}
