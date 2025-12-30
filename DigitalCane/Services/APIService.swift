import Foundation
import CoreLocation
import MapKit

// MARK: - API Service
class APIService {
    static let shared = APIService()
    
    // API Keys loaded from Secrets.plist
    private var googleApiKey: String {
        guard let filePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: filePath),
              let value = plist["GOOGLE_MAPS_API_KEY"] as? String else {
            print("⚠️ Error: GOOGLE_MAPS_API_KEY not found in Secrets.plist")
            return ""
        }
        return value
    }
    
    private var geminiApiKey: String {
        guard let filePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: filePath),
              let value = plist["GEMINI_API_KEY"] as? String else {
            // Fallback: Google API Key를 Gemini에도 사용 가능 (같은 GCP 프로젝트)
            print("⚠️ GEMINI_API_KEY not found, trying GOOGLE_MAPS_API_KEY")
            return googleApiKey
        }
        return value
    }
    
    // MARK: - 1. Intent Analysis using Gemini 2.0 Flash
    // 33% 저렴, 더 빠른 응답, 우수한 JSON 신뢰도
    func analyzeIntent(from text: String, completion: @escaping (LocationIntent?) -> Void) {
        guard !geminiApiKey.isEmpty else {
            print("Gemini API Key is missing")
            completion(nil)
            return
        }
        
        // Gemini 2.0 Flash API 엔드포인트
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(geminiApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 시스템 프롬프트와 사용자 입력
        let systemPrompt = """
        당신은 시각장애인을 위한 음성 안내 서비스 '디지털케인'의 AI 어시스턴트입니다.
        사용자의 대화 내역 전체를 분석하여 최종적인 '목적지(destinationName)'와 '출발지(originName)'를 추출하세요.

        CRITICAL RULES:
        1. **모든 장소 이름은 한국어(Korean)로 추출하세요.**
        2. 사용자의 **가장 최근 입력(Last Turn)**이 이전 대화와 모순된다면, 최근 입력을 우선하여 정보를 업데이트하세요.
        3. 장소 이름이 불완전하거나 발음이 비슷한 오타(예: "항상" -> "하상", "서오울" -> "서울")가 있다면 대화 문맥과 상식적인 지명으로 교정하세요.
        4. "originName"이 명시되지 않았다면 ""로 설정하세요. (UI에서 현재 위치로 자동 처리됨)
        5. "destinationName"을 도저히 알 수 없는 경우에만 ""로 설정하세요. 절대 임의의 장소(예: 서울역)를 지어내지 마세요.
        6. 결과는 반드시 아래의 JSON 형식 하나만 출력하세요. 다른 텍스트는 일절 포함하지 마세요.

        Output format:
        {"destinationName": "추출된 목적지", "originName": "추출된 출발지", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        """
        
        // Gemini API 요청 바디
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemPrompt)\n\n[CONVERSATION HISTORY]\n\(text)\n\n[INSTRUCTION]\nExtract the locations based on the latest turn in the history above. Respond with JSON only."]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.0,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 1024
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error creating JSON body: \(error)")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Gemini Network Error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
                if let content = decodedResponse.candidates?.first?.content?.parts?.first?.text,
                   let jsonData = content.data(using: .utf8) {
                    print("🤖 Gemini Raw JSON: \(content)")
                    
                    // 단일 객체로 파싱 시도
                    if let intent = try? JSONDecoder().decode(LocationIntent.self, from: jsonData) {
                        completion(intent)
                    }
                    // 배열로 파싱 시도 (대화 히스토리 사용 시)
                    else if let intentArray = try? JSONDecoder().decode([LocationIntent].self, from: jsonData),
                            let lastIntent = intentArray.last {
                        // 가장 마지막 의도(최신)를 사용
                        print("📋 Parsed array of \(intentArray.count) intents, using last one")
                        completion(lastIntent)
                    } else {
                        print("Failed to parse Gemini Content")
                        completion(nil)
                    }
                } else {
                    print("No content in Gemini response")
                    if let str = String(data: data, encoding: .utf8) {
                        print("Raw Response: \(str)")
                    }
                    completion(nil)
                }
            } catch {
                print("Gemini Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - 2. MapKit (Apple Maps - 카카오 데이터 기반, 한국 최적화)
    
    /// 장소 검색 (MapKit 기반)
    func searchPlacesMapKit(query: String, completion: @escaping ([Place]?) -> Void) {
        guard !query.isEmpty else {
            completion(nil)
            return
        }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        // 서울 중심으로 검색 범위 설정 (전국 검색 가능)
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            guard let response = response, error == nil else {
                print("MapKit Search Error: \(error?.localizedDescription ?? "Unknown")")
                completion(nil)
                return
            }
            
            let places = response.mapItems.prefix(5).map { item -> Place in
                Place(
                    name: item.name ?? query,
                    address: item.placemark.title ?? "",
                    types: [], // MapKit doesn't provide detailed types
                    coordinate: item.placemark.coordinate
                )
            }
            
            completion(Array(places))
        }
    }
    
    /// 대중교통 경로 검색 (MapKit 기반)
    func fetchRouteMapKit(from originName: String, to destName: String, currentLocation: CLLocation? = nil, completion: @escaping (RouteData?) -> Void) {
        
        // 1. 출발지 MKMapItem 생성
        let getOriginItem: (@escaping (MKMapItem?) -> Void) -> Void = { callback in
            if originName == "Current Location", let current = currentLocation {
                let placemark = MKPlacemark(coordinate: current.coordinate)
                callback(MKMapItem(placemark: placemark))
            } else {
                // 출발지 검색
                self.searchPlacesMapKit(query: originName) { places in
                    guard let place = places?.first else {
                        callback(nil)
                        return
                    }
                    let placemark = MKPlacemark(coordinate: place.coordinate)
                    callback(MKMapItem(placemark: placemark))
                }
            }
        }
        
        // 2. 목적지 MKMapItem 생성
        searchPlacesMapKit(query: destName) { places in
            guard let destPlace = places?.first else {
                completion(nil)
                return
            }
            
            let destPlacemark = MKPlacemark(coordinate: destPlace.coordinate)
            let destItem = MKMapItem(placemark: destPlacemark)
            
            getOriginItem { originItem in
                guard let originItem = originItem else {
                    completion(nil)
                    return
                }
                
                // 3. 경로 요청
                let request = MKDirections.Request()
                request.source = originItem
                request.destination = destItem
                request.transportType = .transit // 대중교통
                
                let directions = MKDirections(request: request)
                directions.calculate { response, error in
                    guard let route = response?.routes.first, error == nil else {
                        print("MapKit Directions Error: \(error?.localizedDescription ?? "Unknown")")
                        completion(nil)
                        return
                    }
                    
                    // 4. MKRoute → RouteData 변환
                    let steps = route.steps.compactMap { self.convertStepMapKit($0) }
                    let totalDuration = "\(Int(route.expectedTravelTime))s"
                    let totalDistance = "\(Int(route.distance))m"
                    
                    completion(RouteData(steps: steps, totalDuration: totalDuration, totalDistance: totalDistance))
                }
            }
        }
    }
    
    // MARK: - 3. Google Routes API (백업용 - 향후 제거 예정)
    func fetchRoute(from origin: String, to destination: String, currentLocation: CLLocation? = nil, completion: @escaping (RouteData?) -> Void) {
        guard !googleApiKey.isEmpty else {
            print("Google API Key is missing")
            completion(nil)
            return
        }
        
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(googleApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // API 키 제한(iOS 앱 제한)을 통과하기 위해 Bundle ID 헤더 추가
        request.addValue(Bundle.main.bundleIdentifier ?? "kr.ac.kaist.assistiveailab.DigitalCane", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.addValue("*", forHTTPHeaderField: "X-Goog-FieldMask") // 모든 필드 요청 (transitDetails 등 포함)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Origin 설정: 좌표가 있으면 좌표 우선, 없으면 주소(텍스트) 사용
        var originBody: [String: Any] = ["address": origin]
        
        if let currentLoc = currentLocation, origin == "Current Location" {
            originBody = [
                "location": [
                    "latLng": [
                        "latitude": currentLoc.coordinate.latitude,
                        "longitude": currentLoc.coordinate.longitude
                    ]
                ]
            ]
        } else if origin == "Current Location" {
             // 좌표가 없으면 실패 처리 (임의 위치인 서울역으로 안내하면 위험함)
             print("Current Location is required but nil")
             completion(nil)
             return
        }
        
        // Google Routes API v2 (Latest Standard 2025)
        // Google Routes API v2 (Latest Standard 2025)
        var requestBody: [String: Any] = [
            "origin": originBody,
            "destination": ["address": destination],
            "travelMode": "TRANSIT",
            "languageCode": "ko",
            "computeAlternativeRoutes": false
        ]
        
        // 설정값 확인: 걷기 최소화(안전 우선)
        if UserDefaults.standard.bool(forKey: "preferLessWalking") {
            requestBody["transitPreferences"] = [
                "routingPreference": "LESS_WALKING"
            ]
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error creating Google Routes body: \(error)")
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Google Routes Network Error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            do {
                // 디버깅용 로그 활성화
                if let str = String(data: data, encoding: .utf8) { 
                    print("📦 Google Routes API Raw Response: \(str)") 
                }
                
                let decodedResponse = try JSONDecoder().decode(GRouteResponse.self, from: data)
                if let route = decodedResponse.routes?.first,
                   let leg = route.legs?.first {
                    
                    // GRouteStep -> RouteStep 변환 (원천 데이터 수집)
                    let allSteps = (leg.steps ?? []).compactMap { self.convertStep($0) }
                    
                    // 도보 단계를 항목에서 제거하고 대중교통 단계에 자연스럽게 녹임
                    var rawTransitSteps: [RouteStep] = []
                    var walkInstructionsBuffer: [String] = []
                    var lastTransitVehicleType: String? = nil
                    
                    for step in allSteps {
                        if step.type == .walk {
                            // 단순 이동은 생략하고, 핵심 정보(역 이름, 입구/출구, 방향)를 버퍼에 보관
                            let instr = step.instruction
                            if !instr.isEmpty {
                                walkInstructionsBuffer.append(instr)
                            }
                        } else {
                            // 대중교통 단계
                            var refinedInstruction = step.instruction
                            let currentVehicleType = step.vehicleType
                            
                            // 버퍼에 쌓인 도보 정보(이동 경로) 통합
                            if !walkInstructionsBuffer.isEmpty {
                                // ⚠️ 정책 반영: 출발/환승 시 '입구/출구' 정보는 상대적이므로 생략 (역 이름 정보만 추출하여 사용)
                                // 입구/출구 숫자가 포함된 정보를 거르고 역 이름 위주로 정리
                                let filteredWalkInfo = walkInstructionsBuffer.map { info -> String in
                                    if info.contains("출구") || info.contains("입구") {
                                        // "서울역 5번 출구" -> "서울역" 처럼 역 이름만 남기거나, 
                                        // 입구 정보만 있는 경우 빈 값으로 만들어 무시
                                        return info.replacingOccurrences(of: "[0-9]+(-[0-9]+)?번\\s*(입구|출구)", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                                    }
                                    return info
                                }.filter { !$0.isEmpty }
                                
                                walkInstructionsBuffer.removeAll()
                                
                                if !filteredWalkInfo.isEmpty {
                                    let walkPrefix = filteredWalkInfo.joined(separator: " 및 ")
                                    
                                    if let stationRange = refinedInstruction.range(of: "에서 ") {
                                        let transitCore = String(refinedInstruction[stationRange.upperBound...])
                                        let stationName = String(refinedInstruction[..<stationRange.lowerBound])
                                        
                                        if walkPrefix.contains(stationName) {
                                            refinedInstruction = "\(walkPrefix)에서 \(transitCore)"
                                        } else {
                                            refinedInstruction = "\(stationName) \(walkPrefix)에서 \(transitCore)"
                                        }
                                    } else {
                                        refinedInstruction = "\(walkPrefix)에서 \(refinedInstruction)"
                                    }
                                }
                            }
                            
                            lastTransitVehicleType = currentVehicleType
                            rawTransitSteps.append(RouteStep(
                                type: step.type,
                                instruction: refinedInstruction,
                                detail: step.detail,
                                action: step.action,
                                stopCount: step.stopCount,
                                duration: step.duration,
                                distance: step.distance,
                                vehicleType: step.vehicleType
                            ))
                        }
                    }
                    
                    // 마지막에 남은 도보 정보(도착지 안내 - 출구 정보 필수) 처리
                    if !walkInstructionsBuffer.isEmpty && !rawTransitSteps.isEmpty {
                        let lastIdx = rawTransitSteps.count - 1
                        let lastStep = rawTransitSteps[lastIdx]
                        
                        // 도착지에서는 '출구' 정보가 매우 중요하므로 그대로 유지
                        let walkSuffix = walkInstructionsBuffer.joined(separator: " 및 ")
                        
                        let connector = walkSuffix.contains("출구") ? "를 통해 나가서" : "로 이동하여"
                        let newInstruction = lastStep.instruction.replacingOccurrences(of: "하차.", with: "하차하여 \(walkSuffix)\(connector) 도착.")
                        
                        rawTransitSteps[lastIdx] = RouteStep(
                            type: lastStep.type,
                            instruction: newInstruction,
                            detail: lastStep.detail,
                            action: lastStep.action,
                            stopCount: lastStep.stopCount,
                            duration: lastStep.duration,
                            distance: lastStep.distance,
                            vehicleType: lastStep.vehicleType
                        )
                    }
 else if !rawTransitSteps.isEmpty {
                        let lastIdx = rawTransitSteps.count - 1
                        let lastStep = rawTransitSteps[lastIdx]
                        if !lastStep.instruction.contains("도착") {
                            let newInstruction = lastStep.instruction.replacingOccurrences(of: "하차.", with: "하차하여 도착.")
                            rawTransitSteps[lastIdx] = RouteStep(
                                type: lastStep.type,
                                instruction: newInstruction,
                                detail: lastStep.detail,
                                action: lastStep.action,
                                stopCount: lastStep.stopCount,
                                duration: lastStep.duration,
                                distance: lastStep.distance,
                                vehicleType: lastStep.vehicleType
                            )
                        }
                    }
                    
                    // 결과가 도보뿐이라 대중교통이 하나도 없는 경우에만 도보 단계 노출
                    let transitResult = rawTransitSteps.isEmpty ? allSteps : rawTransitSteps
                    
                    // 중간 단계의 "하차"를 "하차 및 환승"으로 보완
                    let processedSteps = transitResult.enumerated().map { (index, step) -> RouteStep in
                        if index < transitResult.count - 1 && step.type != .walk {
                            let newInstruction = step.instruction.replacingOccurrences(of: "하차.", with: "하차 및 환승.")
                            return RouteStep(
                                type: step.type,
                                instruction: newInstruction,
                                detail: step.detail,
                                action: step.action,
                                stopCount: step.stopCount,
                                duration: step.duration,
                                distance: step.distance,
                                vehicleType: step.vehicleType
                            )
                        }
                        return step
                    }
                    
                    // 총 소요 시간 및 거리
                    let totalDuration = leg.localizedValues?.duration?.text ?? leg.localizedValues?.staticDuration?.text ?? ""
                    let totalDistance = leg.localizedValues?.distance?.text ?? ""
                    
                    print("✅ Route Integrated: \(processedSteps.count) steps, Duration: \(totalDuration)")
                    let routeData = RouteData(steps: processedSteps, totalDuration: totalDuration, totalDistance: totalDistance)
                    completion(routeData)
                } else {
                    print("⚠️ No routes found in response")
                    completion(nil)
                }
            } catch {
                print("❌ Google Routes Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    /// 애플 지도(MapKit)와 구글 지도(Google Places)를 결합한 하이브리드 주변 검색
    func fetchNearbyPlacesHybrid(latitude: Double, longitude: Double, radius: Double, completion: @escaping ([Place]?, String?) -> Void) {
        // 1. 먼저 애플 네이티브로 검색 시도 (무료/빠름)
        self.fetchNearbyPlacesMapKit(latitude: latitude, longitude: longitude, radius: radius) { nativePlaces, error in
            let foundCount = nativePlaces?.count ?? 0
            
            // 2. 결과가 충분하면(5개 이상) 즉시 반환
            if foundCount >= 5 {
                print("✅ [Hybrid] Apple Native로 충분한 정보(\(foundCount)개) 확보")
                completion(nativePlaces, nil)
                return
            }
            
            // 3. 결과가 부족하면 구글 플레이스 API로 보강 (정밀 정보)
            print("⚠️ [Hybrid] Apple 정보 부족(\(foundCount)개), 구글 API로 보강합니다...")
            self.fetchNearbyPlaces(latitude: latitude, longitude: longitude, radius: radius) { googlePlaces, googleError in
                guard let googlePlaces = googlePlaces else {
                    // 구글도 실패하면 애플 결과라도 반환
                    completion(nativePlaces, error)
                    return
                }
                
                // 두 결과 합치고 중복 제거
                var combined = nativePlaces ?? []
                let nativeNames = Set(combined.map { $0.name })
                
                for gp in googlePlaces {
                    if !nativeNames.contains(gp.name) {
                        combined.append(gp)
                    }
                }
                
                print("✅ [Hybrid] 통합 결과 \(combined.count)개 반환 (Apple + Google 보강)")
                completion(combined, nil)
            }
        }
    }
    
    // MARK: - 3. Nearby Places Search (Native MapKit Version)
    /// 애플 기본 프레임워크(MapKit)를 사용한 주변 장소 검색
    func fetchNearbyPlacesMapKit(latitude: Double, longitude: Double, radius: Double, completion: @escaping ([Place]?, String?) -> Void) {
        // ... (기존 구현 유지)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        // 검색 범위 설정
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        
        // iOS 14+ 에서 지원하는 POI 전용 검색 요청
        if #available(iOS 14.0, *) {
            let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
            // 모든 카테고리 포함
            request.pointOfInterestFilter = .includingAll
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let error = error {
                    print("ℹ️ Native POI service unavailable, switching to generic search: \(error.localizedDescription)")
                    // 실패 시 범용 검색으로 폴백 시도
                    self.performGenericMapKitSearch(region: region, completion: completion)
                    return
                }
                
                guard let response = response else {
                    self.performGenericMapKitSearch(region: region, completion: completion)
                    return
                }
                
                let places = response.mapItems.map { item -> Place in
                    Place(
                        name: item.name ?? "장소",
                        address: item.placemark.title ?? "",
                        types: [], 
                        coordinate: item.placemark.coordinate
                    )
                }
                
                print("✅ [Native MapKit] POI API로 \(places.count)개 검색됨")
                completion(places, nil)
            }
        } else {
            self.performGenericMapKitSearch(region: region, completion: completion)
        }
    }
    
    /// MapKit 범용 검색 폴백 (병렬 카테고리 검색으로 검색량 극대화)
    private func performGenericMapKitSearch(region: MKCoordinateRegion, completion: @escaping ([Place]?, String?) -> Void) {
        // 그룹별 카테고리 정의 (한국 내 POI 밀도를 높이기 위해 분산 검색)
        let categoryGroups: [[MKPointOfInterestCategory]] = [
            [.restaurant, .cafe, .bakery, .brewery], // Food & Drink
            [.store, .pharmacy, .bank, .atm, .postOffice], // Shopping & Services
            [.publicTransport, .gasStation, .parking, .evCharger], // Transportation
            [.hospital, .park, .museum, .library, .school] // Social & Attractions
        ]
        
        var allFoundPlaces: [Place] = []
        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        
        print("🚀 [Multi-Category Search] 고밀도 주변 탐색 시작...")
        
        for group in categoryGroups {
            dispatchGroup.enter()
            let request = MKLocalSearch.Request()
            request.region = region
            request.naturalLanguageQuery = " " // 전범위 검색 유도
            if #available(iOS 13.0, *) {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: group)
                request.resultTypes = .pointOfInterest
            }
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let response = response {
                    let places = self.mapItemsToPlaces(response.mapItems)
                    lock.lock()
                    allFoundPlaces.append(contentsOf: places)
                    lock.unlock()
                }
                dispatchGroup.leave()
            }
        }
        
        // 추가로 '와일드카드' 검색 하나 더 병행
        dispatchGroup.enter()
        let wildcardRequest = MKLocalSearch.Request()
        wildcardRequest.region = region
        wildcardRequest.naturalLanguageQuery = "주변"
        MKLocalSearch(request: wildcardRequest).start { response, error in
            if let response = response {
                let places = self.mapItemsToPlaces(response.mapItems)
                lock.lock()
                allFoundPlaces.append(contentsOf: places)
                lock.unlock()
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            // 중복 제거 (이름과 좌표 기준)
            var uniquePlaces: [Place] = []
            var seenNames = Set<String>()
            
            for place in allFoundPlaces {
                let key = "\(place.name)-\(place.coordinate.latitude)-\(place.coordinate.longitude)"
                if !seenNames.contains(key) {
                    uniquePlaces.append(place)
                    seenNames.insert(key)
                }
            }
            
            print("✅ [Multi-Category Search] 최종 \(uniquePlaces.count)개 장소 통합 발견")
            completion(uniquePlaces, nil)
        }
    }
    
    private func mapItemsToPlaces(_ items: [MKMapItem]) -> [Place] {
        return items.map { item in
            Place(
                name: item.name ?? "알 수 없는 장소",
                address: item.placemark.title ?? "",
                types: [], 
                coordinate: item.placemark.coordinate
            )
        }
    }
    
    // MARK: - 4. Nearby Places Search (Google Places API v1)
    func fetchNearbyPlaces(latitude: Double, longitude: Double, radius: Double, completion: @escaping ([Place]?, String?) -> Void) {
        print("🔍 [NearbyPlaces] Requesting places at: (\(latitude), \(longitude)), radius: \(radius)m")
        
        let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(googleApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue(Bundle.main.bundleIdentifier ?? "kr.ac.kaist.assistiveailab.DigitalCane", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        // 필요한 필드만 요청 (위치 정보 location 추가)
        request.addValue("places.displayName,places.primaryType,places.formattedAddress,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Google Places API 문서에 따르면, includedTypes를 생략하면 모든 장소 유형이 반환됩니다. (Table A 등 필터 제한 없음)
        let requestBody: [String: Any] = [
            "maxResultCount": 20, // 결과 개수 살짝 늘림
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": latitude,
                        "longitude": longitude
                    ],
                    "radius": radius
                ]
            ],
            "languageCode": "ko"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(nil, "요청 데이터 생성 실패")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Places Network Error: \(error.localizedDescription)")
                completion(nil, "서버와 연결할 수 없습니다. 잠시 후 다시 시도해 주세요.")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    let errorMsg = "API 오류: \(httpResponse.statusCode). 키 설정을 확인하세요."
                    print("Projects API Status Code: \(httpResponse.statusCode)")
                    if let data = data, let str = String(data: data, encoding: .utf8) {
                        print("Error Body: \(str)")
                    }
                    completion(nil, errorMsg)
                    return
                }
            }
            
            guard let data = data else {
                completion(nil, "데이터가 비어있습니다.")
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(PlacesResponse.self, from: data)
                let places = decodedResponse.places?.compactMap { place -> Place? in
                    // 위치 정보가 없으면 제외
                    guard let lat = place.location?.latitude, let lng = place.location?.longitude else { return nil }
                    return Place(
                        name: place.displayName?.text ?? "장소",
                        address: place.formattedAddress ?? "",
                        types: place.types ?? [],
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    )
                }
                
                print("✅ [NearbyPlaces] Received \(places?.count ?? 0) places")
                if let places = places, !places.isEmpty {
                    print("📍 Places: \(places.prefix(5).map { $0.name })")
                }
                
                completion(places, nil)
            } catch {
                print("Places Decoding Error: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    print("Raw Res: \(str)")
                }
                completion(nil, "응답 데이터 분석 실패")
            }
        }.resume()
    }
    
    // MARK: - 4. Text Search (POI Validation)
    func searchPlaces(query: String, completion: @escaping ([Place]?) -> Void) {
        guard !query.isEmpty else {
            completion(nil)
            return
        }
        
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(googleApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue(Bundle.main.bundleIdentifier ?? "kr.ac.kaist.assistiveailab.DigitalCane", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.addValue("places.displayName,places.formattedAddress,places.location,places.types", forHTTPHeaderField: "X-Goog-FieldMask")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "textQuery": query,
            "maxResultCount": 5,
            "languageCode": "ko"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Places Search Network Error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            do {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                     print("Places Search API Error: \(httpResponse.statusCode)")
                     completion(nil)
                     return
                }
                
                let decodedResponse = try JSONDecoder().decode(PlacesResponse.self, from: data)
                let places = decodedResponse.places?.compactMap { place -> Place? in
                    guard let lat = place.location?.latitude, let lng = place.location?.longitude else { return nil }
                    return Place(
                        name: place.displayName?.text ?? query,
                        address: place.formattedAddress ?? "",
                        types: place.types ?? [],
                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    )
                }
                
                completion(places)
            } catch {
                print("Places Search Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - Step Conversion
    
    // MapKit Step → App RouteStep 변환 로직
    private func convertStepMapKit(_ mkStep: MKRoute.Step) -> RouteStep? {
        // 도보 경로는 제외
        if mkStep.transportType == .walking {
            return nil
        }
        
        // MapKit의 기본 instructions이 한국어로는 텍스트가 부족할 수 있어 재구성
        // 예: "4호선을 타고 사당역에서 내리세요" 형태로 변환
        
        var action = "이동"
        var lineName = ""
        
        // 핵심 정보 추출 (노선명 등)
        if mkStep.instructions.contains("타고") || mkStep.instructions.contains("탑승") {
             let components = mkStep.instructions.components(separatedBy: " ")
             if let lineIndex = components.firstIndex(where: { $0.contains("호선") || $0.contains("번") }) {
                 lineName = components[lineIndex]
                 action = "\(lineName) 탑승"
             } else {
                 action = mkStep.instructions
             }
        }
        
        // 한글 받침 여부 확인 (을/를 구분) - 로컬 함수 재사용
        func appendJosa(_ text: String) -> String {
            guard let lastChar = text.last, let scalar = lastChar.unicodeScalars.first else { return text + "을(를)" }
            let value = scalar.value
            // 한글 유니코드 범위: 0xAC00 ~ 0xD7A3
            if value >= 0xAC00 && value <= 0xD7A3 {
                let hasBatchim = (value - 0xAC00) % 28 > 0
                return text + (hasBatchim ? "을" : "를")
            }
            return text + "을(를)"
        }
        
        var instruction = mkStep.instructions
        if !lineName.isEmpty {
            let lineWithJosa = appendJosa(lineName)
            instruction = "\(lineWithJosa) 탑승하여 이동하세요."
        }
        
        let distance = Int(mkStep.distance)
        let detail = distance > 0 ? "약 \(distance)m 이동" : ""
        
        return RouteStep(
            type: .ride,
            instruction: instruction,
            detail: detail,
            action: action,
            stopCount: 0,
            duration: "", // MapKit 단계별 시간 정보 부재
            distance: "\(distance)m",
            vehicleType: "SUBWAY" // MapKit은 주로 지하철/철도 위주
        )
    }

    // Google API Step → App RouteStep 변환 로직 (백업용)
    private func convertStep(_ gStep: GRouteStep) -> RouteStep? {
        let duration = gStep.localizedValues?.duration?.text ?? gStep.localizedValues?.staticDuration?.text ?? ""
        let distance = gStep.localizedValues?.distance?.text ?? ""
        
        var type: StepType = .walk
        var action = "도보"
        var instruction = gStep.navigationInstruction?.instructions ?? "이동"
        var stopCount = 0
        
        if let mode = gStep.travelMode, mode == "TRANSIT", let transit = gStep.transitDetails {
            type = .ride
            
            // 🔍 디버그: Google API 데이터 확인 (필요 시 주석 해제)
            // print("🚌 Transit Step Debug:")
            // print("  - transitLine.name: \(transit.transitLine?.name ?? "nil")")
            // print("  - transitLine.shortName: \(transit.transitLine?.shortName ?? "nil")")
            // print("  - vehicle.name: \(transit.transitLine?.vehicle?.name?.text ?? "nil")")
            // print("  - vehicle.type: \(transit.transitLine?.vehicle?.type ?? "nil")")
            
            // 정보 추출
            // 정보 추출
            let rawLine = transit.transitLine?.shortName ?? transit.transitLine?.name ?? ""
            
            // 차량 이름 폴백 (예: "BUS" -> "버스")
            var vehicleName = transit.transitLine?.vehicle?.name?.text
            if vehicleName == nil {
                switch transit.transitLine?.vehicle?.type {
                case "BUS": vehicleName = "버스"
                case "SUBWAY": vehicleName = "지하철"
                case "RAIL": vehicleName = "기차"
                case "FERRY": vehicleName = "배"
                case "TRAM": vehicleName = "트램"
                default: vehicleName = "대중교통"
                }
            }
            
            // 라인 이름 정제
            var lineDisplay = rawLine
            let isNumeric = Int(rawLine) != nil
            let safeVehicleName = vehicleName ?? "대중교통"
            
            // 한국어 최적화 포맷팅
            if safeVehicleName.contains("버스") {
                if lineDisplay.contains("버스") {
                    // "간선버스 143" -> 그대로
                } else {
                    if isNumeric { lineDisplay = "\(rawLine)번 버스" }
                    else { lineDisplay = "\(rawLine) 버스" }
                }
            } else if safeVehicleName.contains("지하철") || safeVehicleName.contains("전철") {
                if isNumeric { lineDisplay = "\(rawLine)호선" }
            } else {
                 if !lineDisplay.isEmpty { lineDisplay = "\(rawLine) (\(safeVehicleName))" }
                 else { lineDisplay = safeVehicleName }
            }
            
            let departure = transit.stopDetails?.departureStop?.name ?? "승차 정류장"
            let arrival = transit.stopDetails?.arrivalStop?.name ?? "하차 정류장"
            let headsign = transit.headsign ?? ""
            stopCount = transit.stopCount ?? 0
            
            // 괄호 제거 (TTS 읽기 오류 방지)
            var directionInfo = ""
            if !headsign.isEmpty && headsign.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
                directionInfo = " \(headsign) 방면으로"
            }
            
            action = "\(lineDisplay) 탑승"
            
            // 한글 받침 여부 확인 (을/를 구분)
            func appendJosa(_ text: String) -> String {
                guard let lastChar = text.last, let scalar = lastChar.unicodeScalars.first else { return text + "을(를)" }
                let value = scalar.value
                // 한글 유니코드 범위: 0xAC00 ~ 0xD7A3
                if value >= 0xAC00 && value <= 0xD7A3 {
                    let hasBatchim = (value - 0xAC00) % 28 > 0
                    return text + (hasBatchim ? "을" : "를")
                }
                return text + "을(를)" // 한글이 아니면 기본값
            }
            
            let lineWithJosa = appendJosa(lineDisplay)
            
            // 자연스러운 문장형 복구 (조사 완벽 처리)
            // 예: "서울역에서 143번 버스를 타고 고속터미널 방면으로 5개 정류장 이동 후 신사역에서 하차."
            if stopCount > 0 {
                instruction = "\(departure)에서 \(lineWithJosa) 타고\(directionInfo) \(stopCount)개 정류장 이동 후 \(arrival)에서 하차."
            } else {
                instruction = "\(departure)에서 \(lineWithJosa) 타고\(directionInfo) \(arrival)까지 이동 후 하차."
            }
            
            // 탑승 시간 정보 (명확하게 표시)
            let distanceText = gStep.localizedValues?.distance?.text ?? ""
            var detailInfo = ""
            if !duration.isEmpty {
                detailInfo = "🚌 탑승 시간 약 \(duration)"
                if !distanceText.isEmpty {
                    detailInfo += " (\(distanceText))"
                }
            } else if !distanceText.isEmpty {
                detailInfo = "🚌 \(distanceText) 이동"
            }
            
            return RouteStep(type: .board,
                             instruction: instruction,
                             detail: detailInfo,
                             action: action,
                             stopCount: stopCount,
                             duration: duration,
                             distance: distance,
                             vehicleType: transit.transitLine?.vehicle?.type)
        }
        
        // 도보 단계 처리 (불필요한 파편화 제거)
        let distanceNum = Int(distance.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)) ?? 0
        let originalInstruction = gStep.navigationInstruction?.instructions ?? ""
        
        // 1. 아주 짧은 의미 없는 도보(2m 이하)는 필터링 (단, 입/출구 정보가 있으면 유지)
        if distanceNum < 3 && !originalInstruction.contains("출구") && !originalInstruction.contains("입구") {
            return nil
        }
        
        if distanceNum > 0 {
            var walkInstruction = ""
            var walkDetail = ""
            
            // 핵심 안내 내용 (역 이름, 출구/입구/방향 등) 추출
            let isStationTarget = originalInstruction.contains("까지") || originalInstruction.contains("역")
            let isGateInfo = originalInstruction.contains("출구") || originalInstruction.contains("입구") || originalInstruction.contains("방향")
            
            if !originalInstruction.isEmpty && (isStationTarget || isGateInfo) {
                var cleaned = originalInstruction.replacingOccurrences(of: " 이용", with: "")
                
                // 숫자 뒤에 '번'이 없으면 추가 (예: "5 입구" -> "5번 입구")
                let pattern = "([0-9]+(-[0-9]+)?)\\s*(입구|출구)"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(location: 0, length: cleaned.utf16.count)
                    cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "$1번 $3")
                }
                
                walkInstruction = cleaned.trimmingCharacters(in: .whitespaces)
            } else if distanceNum > 100 {
                // 특정 거점 정보가 없더라도 도보가 100m 이상이면 안내 (기능 필수 요청 반영)
                walkInstruction = "약 \(distanceNum)m 이동하세요"
            } else {
                walkInstruction = ""
            }
            
            // 필수 정보(역 이름 등)가 있으면 거리와 상관없이 유지
            if walkInstruction.isEmpty && !isStationTarget && distanceNum < 100 { return nil }
            
            walkDetail = duration.isEmpty ? "" : "약 \(duration)"
            
            return RouteStep(type: .walk,
                             instruction: walkInstruction,
                             detail: walkDetail,
                             action: "도보 \(distanceNum)m",
                             stopCount: 0,
                             duration: duration,
                             distance: distance,
                             vehicleType: nil)
        }
        
        // 거리 정보도 없는 도보 단계는 제외
        return nil
    }
}

// MARK: - Data Models (App Internal)

struct LocationIntent: Codable {
    let originName: String? // Optional starting point
    let destinationName: String
    let transportMode: String
    // 대화형 정교화를 위한 필드
    let clarificationNeeded: Bool?
    let clarificationQuestion: String?
}

struct RouteData {
    let steps: [RouteStep]
    let totalDuration: String
    let totalDistance: String
}

enum StepType {
    case walk, wait, board, ride, alight
}

struct RouteStep {
    let type: StepType
    let instruction: String
    let detail: String
    let action: String
    let stopCount: Int
    let duration: String?
    let distance: String?
    let vehicleType: String? // "BUS", "SUBWAY" 등
}

// MARK: - Gemini Codable Models

struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent?
}

struct GeminiContent: Decodable {
    let parts: [GeminiPart]?
}

struct GeminiPart: Decodable {
    let text: String?
}

// MARK: - Google Routes API Codable Models

struct GRouteResponse: Decodable {
    let routes: [GRoute]?
}

struct GRoute: Decodable {
    let legs: [GRouteLeg]?
}

struct GRouteLeg: Decodable {
    let steps: [GRouteStep]?
    let duration: String? // "123s"
    let localizedValues: GLocalizedValues?
}

struct GRouteStep: Decodable {
    let navigationInstruction: GNavigationInstruction?
    let localizedValues: GLocalizedValues?
    let travelMode: String? // "WALK", "TRANSIT"
    let transitDetails: GTransitDetails?
}

struct GNavigationInstruction: Decodable {
    let instructions: String?
}

struct GLocalizedValues: Decodable {
    let duration: GTextValue?
    let staticDuration: GTextValue?
    let distance: GTextValue?
}

struct GTextValue: Decodable {
    let text: String?
}

struct GTransitDetails: Decodable {
    let stopDetails: GStopDetails?
    let transitLine: GTransitLine?
    let headsign: String?
    let stopCount: Int? // 정류장 수 추가
}

struct GStopDetails: Decodable {
    let departureStop: GStop?
    let arrivalStop: GStop?
}

struct GStop: Decodable {
    let name: String?
}

struct GTransitLine: Decodable {
    let name: String?
    let shortName: String?
    let vehicle: GTransitVehicle?
    
    enum CodingKeys: String, CodingKey {
        case name
        case shortName = "nameShort"  // JSON은 nameShort, Swift는 shortName
        case vehicle
    }
}

struct GTransitVehicle: Decodable {
    let name: GTextValue?
    let type: String? // "BUS", "SUBWAY", "RAIL"
}



// ... (Existing models) ...

// MARK: - Places API Models

struct PlacesResponse: Decodable {
    let places: [GPlace]?
}

struct GPlace: Decodable {
    let displayName: GDisplayName?
    let formattedAddress: String?
    let types: [String]?
    let location: GLocation?
}

struct GLocation: Decodable {
    let latitude: Double
    let longitude: Double
}

struct GDisplayName: Decodable {
    let text: String?
}

// App-side Place Model
struct Place: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let types: [String]
    let coordinate: CLLocationCoordinate2D
    
    var accessibleDescription: String {
        return "\(name). \(address)."
    }
}
