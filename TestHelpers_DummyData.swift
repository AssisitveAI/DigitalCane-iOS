import SwiftUI
import CoreLocation

/// 주변 탐색 기능 빠른 테스트용 더미 데이터
/// 
/// 사용 방법:
/// 1. NearbyExploreView.swift의 fetchPlaces() 함수 맨 위에 다음 코드 추가:
///    ```
///    // 테스트용: 더미 데이터로 UI 확인
///    self.places = DummyPlacesData.generateTestPlaces()
///    self.isLoading = false
///    startScanning()
///    return // API 호출 생략
///    ```
/// 
/// 2. 앱 실행 후 "디지털 지팡이" 탭에서 "준비됨: 5개의 장소" 표시 확인
/// 3. 실제 기기에서 휴대폰 흔들면 "강남역", "스타벅스" 등 음성 재생
/// 4. 테스트 완료 후 위 코드 삭제하고 실제 API 사용

struct DummyPlacesData {
    static func generateTestPlaces() -> [Place] {
        // 서울 강남 중심 (37.5665, 126.9780)
        let center = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
        
        return [
            Place(
                name: "강남역",
                address: "서울특별시 강남구",
                types: ["transit_station"],
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude + 0.001,  // 북쪽
                    longitude: center.longitude
                )
            ),
            Place(
                name: "스타벅스 강남점",
                address: "서울특별시 강남구 강남대로",
                types: ["cafe"],
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude,
                    longitude: center.longitude + 0.001  // 동쪽
                )
            ),
            Place(
                name: "신한은행",
                address: "서울특별시 강남구",
                types: ["bank"],
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude - 0.001,  // 남쪽
                    longitude: center.longitude
                )
            ),
            Place(
                name: "GS25 편의점",
                address: "서울특별시 강남구",
                types: ["convenience_store"],
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude,
                    longitude: center.longitude - 0.001  // 서쪽
                )
            ),
            Place(
                name: "교보문고",
                address: "서울특별시 강남구",
                types: ["book_store"],
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude + 0.0005,
                    longitude: center.longitude + 0.0005  // 북동쪽
                )
            )
        ]
    }
}
