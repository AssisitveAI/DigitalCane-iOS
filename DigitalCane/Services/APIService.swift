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
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(geminiApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 시스템 프롬프트와 사용자 입력
        let systemPrompt = """
        You are 'Digital Cane', a smart mobility assistant for visually impaired users IN SOUTH KOREA.
        The user interacts conversationally (e.g., "I'd like to go to...", "How can I get to...?", "Where is...?", "Guide me to...").
        This is NOT a sat-nav; users ask for guidance naturally. Do NOT expect sticking to "Go to X".
        Your task is to extract the intended 'destinationName' and 'originName' from these natural inquiries.
        
        CRITICAL RULES:
        0. **ALWAYS EXTRACT PLACE NAMES IN KOREAN (한국어)** - NEVER translate to English! Use the Korean name.
        1. Extract names exactly as spoken. Do not guess or hallucinate.
        2. If the user does not specify a destination, set "destinationName" to "".
        3. If the user specifies a starting point (e.g., "From Seoul Station to Busan"), set "originName" to that place. Otherwise, set "originName" to "".
        4. Default "transportMode" to "TRANSIT".
        5. If the request is ambiguous (e.g., distinguishing "Sin-chon" as Train Station vs Subway, or "Gangnam" as Station vs Area), set "clarificationNeeded" to true and provide a specific Korean question in "clarificationQuestion" (e.g., "신촌역 기차역으로 갈까요, 지하철역으로 갈까요?").
        6. If the input is unintelligible or irrelevant, set "clarificationNeeded" to true and ask "잘 못 들었습니다. 목적지를 다시 말씀해 주시겠어요?" in "clarificationQuestion".
        7. Context Inference: You may infer the specific location from context (e.g. 'Seoul School' -> 'Seoul City Hall'), BUT if multiple candidates exist (e.g. 'Terminal' in Seoul has Gangnam/Dong Seoul/Nambu), DO NOT GUESS. Set "clarificationNeeded" to true and ask "어느 터미널로 갈까요?" in "clarificationQuestion".
        
        Examples:
        - User: "서울역 가는 법 좀 알려줘" -> {"destinationName": "서울역", "originName": "", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        - User: "강남에서 코엑스까지 어떻게 가?" -> {"destinationName": "코엑스", "originName": "강남", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        - User: "서울맹학교에서 시청으로 가고 싶어" -> {"destinationName": "서울시청", "originName": "서울맹학교", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        - User: "From Yonsei to Seoul Station" -> {"destinationName": "서울역", "originName": "연세대학교", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        
        Respond ONLY in valid JSON format. No markdown, no explanation.
        """
        
        // Gemini API 요청 바디
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(systemPrompt)\n\nUser input: \(text)"]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.1  // 일관된 JSON 출력을 위해 낮은 온도
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
                    
                    if let intent = try? JSONDecoder().decode(LocationIntent.self, from: jsonData) {
                        completion(intent)
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
                    
                    completion(RouteData(steps: steps, totalDuration: totalDuration))
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
                    
                    // GRouteStep -> RouteStep 변환
                    let rawSteps = (leg.steps ?? []).compactMap { self.convertStep($0) }
                    
                    // 환승 명시화 로직: 마지막 단계가 아니면 "하차" -> "하차 및 환승"으로 변경
                    let steps = rawSteps.enumerated().map { (index, step) -> RouteStep in
                        if index < rawSteps.count - 1 {
                            let newInstruction = step.instruction.replacingOccurrences(of: "하차.", with: "하차 및 환승.")
                            return RouteStep(
                                type: step.type,
                                instruction: newInstruction,
                                detail: step.detail,
                                action: step.action,
                                stopCount: step.stopCount
                            )
                        }
                        return step
                    }
                    
                    // 총 소요 시간: localizedValues 우선 사용 (형식: "1시간 4분") -> 없으면 초 단위 계산
                    var totalDuration = leg.localizedValues?.duration?.text ?? leg.localizedValues?.staticDuration?.text
                    
                    if totalDuration == nil {
                        let durationSeconds = (Int(leg.duration?.replacingOccurrences(of: "s", with: "") ?? "0") ?? 0)
                        totalDuration = "약 \(durationSeconds / 60)분"
                    }
                    
                    print("✅ Route Parsed: \(steps.count) steps, Duration: \(totalDuration ?? "")")
                    let routeData = RouteData(steps: steps, totalDuration: totalDuration ?? "")
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
    
    // MARK: - 3. Nearby Places Search (Google Places API v1)
    // MARK: - 3. Nearby Places Search (Google Places API v1)
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
        
        // MapKit의 instructions는 이미 한국어로 잘 제공됨
        // 예: "4호선을 타고 사당역에서 내리세요"
        let instruction = mkStep.instructions
        
        // action 추출 (간단히 instructions의 핵심 부분 사용)
        var action = "이동"
        if instruction.contains("타고") || instruction.contains("탑승") {
            // "XXX을 타고" 형태에서 노선명 추출
            let components = instruction.components(separatedBy: " ")
            if let lineIndex = components.firstIndex(where: { $0.contains("호선") || $0.contains("번") }) {
                action = "\(components[lineIndex]) 탑승"
            } else if components.count > 0 {
                action = components.prefix(2).joined(separator: " ")
            }
        }
        
        let distance = Int(mkStep.distance)
        let detail = distance > 0 ? "약 \(distance)m 이동" : ""
        
        return RouteStep(
            type: .ride,
            instruction: instruction,
            detail: detail,
            action: action,
            stopCount: 0  // MapKit은 정류장 수를 직접 제공하지 않음
        )
    }

    // Google API Step → App RouteStep 변환 로직 (백업용)
    private func convertStep(_ gStep: GRouteStep) -> RouteStep? {
        // 도보 경로는 제외 (사용자 요청: 정류장/역 이름, 버스 번호 등만 제공)
        if gStep.travelMode == "WALK" {
            return nil
        }
        
        let detail = gStep.localizedValues?.duration?.text ?? gStep.localizedValues?.staticDuration?.text ?? ""
        var type: StepType = .ride
        var action = "이동"
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
            
            // headsign 검증
            var directionInfo = ""
            if !headsign.isEmpty && headsign.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
                directionInfo = " (\(headsign) 방면)"
            }
            
            action = "\(lineDisplay) 탑승"
            
            instruction = "\(departure) 승차. \(lineDisplay) 탑승\(directionInfo). \(stopCount)개 정류장 이동 후 \(arrival)에서 하차."
            
            // 거리 정보 폴백 (localizedValues.distance)
            let distanceText = gStep.localizedValues?.distance?.text ?? ""
            let detailInfo = !distanceText.isEmpty ? "\(detail). \(distanceText) 이동." : "\(detail)."
            
            return RouteStep(type: .board,
                             instruction: instruction,
                             detail: "이동 시간 약 \(detailInfo)",
                             action: action,
                             stopCount: stopCount)
        }
        
        // 기타/Fallback
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
}

enum StepType {
    case walk, wait, board, ride, alight
}

struct RouteStep {
    let type: StepType
    let instruction: String
    let detail: String
    let action: String
    let stopCount: Int // 정류장 개수 추가
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
