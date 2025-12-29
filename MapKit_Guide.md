# Apple MapKit 사용 가이드

## 개요
Apple MapKit은 iOS 네이티브 지도 프레임워크로, **한국에서는 카카오맵 데이터를 사용**합니다.

---

## 주요 장점

### 1. 완전 무료
- API 키 불필요
- 호출 제한 없음
- 추가 비용 제로

### 2. 한국 데이터 품질
- 카카오맵 파트너십
- Google Maps보다 정확
- 실시간 대중교통 정보

### 3. 네이티브 통합
- iOS 시스템 라이브러리
- 안정성 최고
- 자동 업데이트

---

## 주요 API

### 1. 장소 검색 (MKLocalSearch)
```swift
import MapKit

func searchPlace(query: String) {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query  // "서울역"
    
    let search = MKLocalSearch(request: request)
    search.start { response, error in
        guard let response = response else { return }
        
        for item in response.mapItems {
            print("이름: \(item.name ?? "")")
            print("주소: \(item.placemark.title ?? "")")
            print("좌표: \(item.placemark.coordinate)")
        }
    }
}
```

### 2. 대중교통 경로 (MKDirections)
```swift
func getTransitRoute(from origin: MKMapItem, to destination: MKMapItem) {
    let request = MKDirections.Request()
    request.source = origin
    request.destination = destination
    request.transportType = .transit  // 대중교통
    
    let directions = MKDirections(request: request)
    directions.calculate { response, error in
        guard let route = response?.routes.first else { return }
        
        for step in route.steps {
            print("지시: \(step.instructions)")
            print("거리: \(step.distance)m")
        }
    }
}
```

---

## 응답 구조

### MKRoute.Step
```swift
step.instructions  // "4호선을 타고 사당역에서 내리세요"
step.distance      // 거리 (미터)
step.transportType // .transit, .walking
step.polyline      // 경로 라인
```

### MKMapItem
```swift
item.name                      // "서울역"
item.placemark.coordinate      // CLLocationCoordinate2D
item.placemark.title           // "서울특별시 용산구..."
item.phoneNumber               // 전화번호 (있으면)
```

---

## 제한 사항

### 1. 실시간 버스 도착 정보
- ❌ MapKit에서는 제공 안 함
- 대안: 별도 공공 API 사용 (서울 TOPIS)

### 2. 환승 상세 정보
- 기본 환승 정보는 제공
- 상세 동선(몇 호차, 몇 번 출구)은 제한적

### 3. 경로 커스터마이징
- 계단 회피, 엘리베이터만 사용 등 옵션 없음

---

## Google Maps와 비교

| 기능 | Google Maps | Apple MapKit |
|------|-------------|--------------|
| 장소 검색 | ⚠️ (한국 부실) | ✅ (카카오 데이터) |
| 대중교통 경로 | ⚠️ (한국 부실) | ✅ (정확) |
| 버스 번호 | "간선 143" | "143" |
| API 키 | 필요 | **불필요** |
| 비용 | 무료 (조건부) | **완전 무료** |
| 실시간 정보 | ❌ | ⚠️ (제한적) |

---

## 구현 예시

### 전체 플로우
```swift
import MapKit

class MapKitService {
    // 1. 장소 검색
    func searchPlace(query: String, completion: @escaping (MKMapItem?) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            completion(response?.mapItems.first)
        }
    }
    
    // 2. 대중교통 경로
    func getRoute(from origin: MKMapItem, to dest: MKMapItem, completion: @escaping (MKRoute?) -> Void) {
        let request = MKDirections.Request()
        request.source = origin
        request.destination = dest
        request.transportType = .transit
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            completion(response?.routes.first)
        }
    }
}
```

---

## 다음 단계

1. `APIService.swift`에 MapKit 함수 추가
2. Google Maps 코드는 주석 처리 (백업)
3. 테스트 실행

MapKit 전환을 진행하시겠습니까?
