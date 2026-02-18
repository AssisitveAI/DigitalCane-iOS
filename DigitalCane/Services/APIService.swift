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
    

    // MARK: - Helper: Network Check
    private func checkNetwork() throws {
        if !NetworkMonitor.shared.isConnected {
            throw DigitalCaneError.notConnected
        }
    }

    // MARK: - 1. Intent Analysis using Gemini 3 Flash Preview
    // 최신 모델, 최고 수준의 한국어 이해력 및 JSON 신뢰도
    func analyzeIntent(from text: String) async throws -> LocationIntent? {
        try checkNetwork()
        guard !geminiApiKey.isEmpty else {
            throw DigitalCaneError.missingAPIKey
        }
        
        // Gemini 3 Flash Preview API 엔드포인트
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=\(geminiApiKey)")!
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
        {"destinationName": "추출된 목적지", "originName": "추출된 출발지", "transportMode": "TRANSIT", "preferredTransportModes": ["BUS", "SUBWAY"], "routingPreference": "LESS_WALKING", "clarificationNeeded": false, "clarificationQuestion": null}

        
        Usage Guide for 'preferredTransportModes':
        - If user says "버스로 가고 싶어" -> ["BUS"]
        - If user says "지하철이나 기차로 안내해줘" -> ["SUBWAY", "RAIL"]
        - If user doesn't specify or says "상관없어" -> null
        - Supported values: "BUS", "SUBWAY", "RAIL"
        
        Usage Guide for 'routingPreference':
        - If user says "최소 환승으로 가고 싶어", "갈아타기 싫어" -> "FEWER_TRANSFERS"
        - If user says "걷기 싫어", "도보 최소화해줘", "다리가 아파" -> "LESS_WALKING"
        - If user says nothing specific -> null
        - Supported values: "LESS_WALKING", "FEWER_TRANSFERS"
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
             throw DigitalCaneError.parsingError("JSON Body Creation Failed: \(error.localizedDescription)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DigitalCaneError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw DigitalCaneError.quotaExceeded
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DigitalCaneError.networkError("Gemini API Error: \(httpResponse.statusCode)")
        }
            
        do {
            let decodedResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            if let content = decodedResponse.candidates?.first?.content?.parts?.first?.text,
               let jsonData = content.data(using: .utf8) {
                print("🤖 Gemini Raw JSON: \(content)")
                
                // 단일 객체로 파싱 시도
                if let intent = try? JSONDecoder().decode(LocationIntent.self, from: jsonData) {
                    return intent
                }
                // 배열로 파싱 시도 (대화 히스토리 사용 시)
                else if let intentArray = try? JSONDecoder().decode([LocationIntent].self, from: jsonData),
                        let lastIntent = intentArray.last {
                    // 가장 마지막 의도(최신)를 사용
                    print("📋 Parsed array of \(intentArray.count) intents, using last one")
                    return lastIntent
                } else {
                    print("Failed to parse Gemini Content")
                    return nil
                }
            } else {
                print("No content in Gemini response")
                if let str = String(data: data, encoding: .utf8) {
                    print("Raw Response: \(str)")
                }
                return nil
            }
        } catch {
            print("Gemini Decoding Error: \(error)")
            throw DigitalCaneError.parsingError(error.localizedDescription)
        }
    }

    // MARK: - 2. MapKit (Apple Maps - 카카오 데이터 기반, 한국 최적화)
    
    /// 장소 검색 (MapKit 기반)
    func searchPlacesMapKit(query: String) async throws -> [Place] {
        guard !query.isEmpty else { return [] }
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        // 서울 중심으로 검색 범위 설정 (전국 검색 가능)
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        
        let places = response.mapItems.prefix(5).map { item -> Place in
            Place(
                name: item.name ?? query,
                address: item.placemark.title ?? "",
                types: [], // MapKit doesn't provide detailed types
                coordinate: item.placemark.coordinate
            )
        }
        
        return Array(places)
    }
    
    /// 대중교통 경로 검색 (MapKit 기반)
    func fetchRouteMapKit(from originName: String, to destName: String, currentLocation: CLLocation? = nil) async throws -> RouteData? {
        // 1. 목적지 MKMapItem 생성
        let destPlaces = try await searchPlacesMapKit(query: destName)
        guard let destPlace = destPlaces.first else { return nil }
        
        let destPlacemark = MKPlacemark(coordinate: destPlace.coordinate)
        let destItem = MKMapItem(placemark: destPlacemark)
        
        // 2. 출발지 MKMapItem 생성
        let originItem: MKMapItem
        if originName == "Current Location", let current = currentLocation {
            let placemark = MKPlacemark(coordinate: current.coordinate)
            originItem = MKMapItem(placemark: placemark)
        } else {
            let originPlaces = try await searchPlacesMapKit(query: originName)
            guard let originPlace = originPlaces.first else { return nil }
            let placemark = MKPlacemark(coordinate: originPlace.coordinate)
            originItem = MKMapItem(placemark: placemark)
        }
        
        // 3. 경로 요청
        let request = MKDirections.Request()
        request.source = originItem
        request.destination = destItem
        request.transportType = .transit // 대중교통
        
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        
        guard let route = response.routes.first else { return nil }
        
        // 4. MKRoute → RouteData 변환
        let steps = route.steps.compactMap { self.convertStepMapKit($0) }
        let totalDuration = "\(Int(route.expectedTravelTime))s"
        let totalDistance = "\(Int(route.distance))m"
        
        return RouteData(steps: steps, totalDuration: totalDuration, totalDistance: totalDistance)
    }
    
    // MARK: - 3. Google Routes API (백업용 -> 메인 대중교통 엔진)
    func fetchRoute(from origin: String, 
                    to destination: String, 
                    currentLocation: CLLocation? = nil, 
                    preferredModes: [String]? = nil,
                    routingPreference: String? = nil) async throws -> (RouteData?, Bool) { // Bool: isFallbackApplied
        try checkNetwork()
        guard !googleApiKey.isEmpty else {
            throw DigitalCaneError.missingAPIKey
        }
        
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(googleApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // API 키 제한(iOS 앱 제한)을 통과하기 위해 Bundle ID 헤더 추가
        request.addValue(Bundle.main.bundleIdentifier ?? "kr.ac.kaist.assistiveailab.DigitalCane", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        
        let fields = [
            "routes.legs.steps.navigationInstruction",
            "routes.legs.steps.transitDetails",
            "routes.legs.steps.localizedValues",
            "routes.legs.steps.travelMode",
            "routes.legs.distanceMeters",
            "routes.legs.duration",
            "routes.legs.localizedValues"
        ].joined(separator: ",")
        
        request.addValue(fields, forHTTPHeaderField: "X-Goog-FieldMask")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Origin 설정
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
             throw DigitalCaneError.locationError("Current Location required but nil")
        }
        
        // Google Routes API v2 (Latest Standard 2025)
        var requestBody: [String: Any] = [
            "origin": originBody,
            "destination": ["address": destination],
            "travelMode": "TRANSIT",
            "languageCode": "ko",
            "computeAlternativeRoutes": false
        ]
        
        // 1. transitPreferences 객체 준비
        var transitPreferences: [String: Any] = [:]
        
        // 2. 도보 최소화 및 환승 최소화 (사용자 의도 우선 반영)
        if let preference = routingPreference {
            transitPreferences["routingPreference"] = preference
            print("🔹 Applying Routing Preference: \(preference)")
        } else if UserDefaults.standard.bool(forKey: "preferLessWalking") {
            transitPreferences["routingPreference"] = "LESS_WALKING"
        } else if UserDefaults.standard.bool(forKey: "preferFewerTransfers") {
            transitPreferences["routingPreference"] = "FEWER_TRANSFERS"
        }
        
        // 3. 사용자 선호 교통수단
        if let modes = preferredModes, !modes.isEmpty {
            transitPreferences["allowedTravelModes"] = modes
            print("🔹 Applying Travel Preference: \(modes)")
        }
        
        if !transitPreferences.isEmpty {
            requestBody["transitPreferences"] = transitPreferences
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DigitalCaneError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            throw DigitalCaneError.quotaExceeded
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DigitalCaneError.networkError("Google Routes API Error: \(httpResponse.statusCode)")
        }
        
        do {
            if let str = String(data: data, encoding: .utf8) { 
                print("📦 Google Routes API Raw Response: \(str)") 
            }
            
            let decodedResponse = try JSONDecoder().decode(GRouteResponse.self, from: data)
            if let route = decodedResponse.routes?.first,
               let leg = route.legs?.first {
                
                // GRouteStep -> RouteStep 변환
                let allSteps = (leg.steps ?? []).compactMap { self.convertStep($0) }
                
                // 도보 단계를 항목에서 제거하고 대중교통 단계에 자연스럽게 녹임
                var rawTransitSteps: [RouteStep] = []
                var walkInstructionsBuffer: [String] = []
                var lastTransitVehicleType: String? = nil
                
                for step in allSteps {
                    if step.type == .walk {
                        let instr = step.instruction
                        if !instr.isEmpty {
                            walkInstructionsBuffer.append(instr)
                        }
                    } else {
                        // 대중교통 단계
                        var refinedInstruction = step.instruction
                        let currentVehicleType = step.vehicleType
                        
                        // 버퍼에 쌓인 도보 정보 통합
                        if !walkInstructionsBuffer.isEmpty {
                            let filteredWalkInfo = walkInstructionsBuffer.map { info -> String in
                                if info.contains("출구") || info.contains("입구") {
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
                
                // 마지막에 남은 도보 정보 처리
                if !walkInstructionsBuffer.isEmpty && !rawTransitSteps.isEmpty {
                    let lastIdx = rawTransitSteps.count - 1
                    let lastStep = rawTransitSteps[lastIdx]
                    
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
                } else if !rawTransitSteps.isEmpty {
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
                
                let transitResult = rawTransitSteps.isEmpty ? allSteps : rawTransitSteps
                
                // 중간 단계 "하차" -> "하차 및 환승"
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
                
                let totalDuration = leg.localizedValues?.duration?.text ?? leg.localizedValues?.staticDuration?.text ?? ""
                let totalDistance = leg.localizedValues?.distance?.text ?? ""
                
                print("✅ Route Integrated: \(processedSteps.count) steps, Duration: \(totalDuration)")
                let routeData = RouteData(steps: processedSteps, totalDuration: totalDuration, totalDistance: totalDistance)
                return (routeData, false)
            } else {
                print("⚠️ No routes found in response")
                
                // Fallback Logic
                if let modes = preferredModes, !modes.isEmpty {
                    print("🔄 Fallback: Retrying with ALL modes...")
                    // 재귀 호출
                    let (retryData, _) = try await self.fetchRoute(from: origin, to: destination, currentLocation: currentLocation, preferredModes: nil, routingPreference: nil)
                    return (retryData, true)
                } else {
                    return (nil, false)
                }
            }
        } catch {
            print("❌ Google Routes Decoding Error: \(error)")
            throw DigitalCaneError.parsingError(error.localizedDescription)
        }
    }
    

    
    // MARK: - 3. Nearby Places Search (Native MapKit Version)
    /// 애플 기본 프레임워크(MapKit)를 사용한 주변 장소 검색

    
    // MARK: - 4. Nearby Places Search (Google Places API v1)
    func fetchNearbyPlaces(latitude: Double, longitude: Double, radius: Double) async throws -> [Place] {
        try checkNetwork()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        
        // 1. 캐시 확인
        if let cached = LocationCache.shared.getCachedPlaces(for: location) {
            print("📦 [Cache] Using cached places for (\(latitude), \(longitude))")
            return cached
        }
        
        print("🔍 [NearbyPlaces] Requesting places at: (\(latitude), \(longitude)), radius: \(radius)m")
        
        guard !googleApiKey.isEmpty else {
            throw DigitalCaneError.missingAPIKey
        }
        
        let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(googleApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue(Bundle.main.bundleIdentifier ?? "kr.ac.kaist.assistiveailab.DigitalCane", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.addValue("places.displayName,places.primaryType,places.formattedAddress,places.location,places.accessibilityOptions,places.businessStatus", forHTTPHeaderField: "X-Goog-FieldMask")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "maxResultCount": 20,
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
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw DigitalCaneError.networkError("Invalid Response Type")
        }
        
        if httpResponse.statusCode != 200 {
            throw DigitalCaneError.networkError("Google Places API Error: \(httpResponse.statusCode)")
        }
        
        guard !data.isEmpty else {
            return []
        }
        
        let decodedResponse = try JSONDecoder().decode(PlacesResponse.self, from: data)
        let places = decodedResponse.places?.compactMap { place -> Place? in
            guard let lat = place.location?.latitude, let lng = place.location?.longitude else { return nil }
            if let status = place.businessStatus, status != "OPERATIONAL" {
                return nil
            }
            guard let name = place.displayName?.text, !name.isEmpty else { return nil }
            
            return Place(
                name: name,
                address: place.formattedAddress ?? "",
                types: place.types ?? [],
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                isWheelchairAccessible: place.accessibilityOptions?.wheelchairAccessibleEntrance ?? false
            )
        }
        
        // 중복 제거 및 캐시 저장
        var uniquePlaces: [Place] = []
        if let places = places {
            for place in places {
                let isDuplicate = uniquePlaces.contains { existingPlace in
                    if existingPlace.name == place.name {
                        let loc1 = CLLocation(latitude: existingPlace.coordinate.latitude, longitude: existingPlace.coordinate.longitude)
                        let loc2 = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                        return loc1.distance(from: loc2) < 30.0
                    }
                    return false
                }
                
                if !isDuplicate {
                    uniquePlaces.append(place)
                }
            }
        }
        
        // 2. 캐시 저장
        LocationCache.shared.setCachedPlaces(uniquePlaces, for: location)
        
        print("✅ [NearbyPlaces] Received \(uniquePlaces.count) places (Unique)")
        return uniquePlaces
    }
    
    // MARK: - 5. Overpass API (Building Geometry)
    
    /// Overpass API를 사용하여 주변 건물의 형상(Polygon) 데이터를 가져옵니다.
    /// - Parameters:
    ///   - location: 검색 중심 좌표
    ///   - radius: 검색 반경 (미터, 기본값 30m)
    // MARK: - 5. Overpass API (Building Geometry)
    
    /// Overpass API를 사용하여 주변 건물의 형상(Polygon) 데이터를 가져옵니다.
    func fetchNearbyBuildings(at location: CLLocationCoordinate2D, radius: Double = 30.0) async throws -> [BuildingPolygon] {
        try checkNetwork()
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        // 1. 캐시 확인
        if let cached = LocationCache.shared.getCachedBuildings(for: clLocation) {
            print("📦 [Cache] Using cached buildings for (\(location.latitude), \(location.longitude))")
            return cached
        }
        
        let lat = location.latitude
        let lon = location.longitude
        
        let query = """
        [out:json][timeout:10];
        (
          // 1. 주변 정밀 탐색 (반경 \(radius)m)
          way["building"](around:\(radius),\(lat),\(lon));
          relation["building"](around:\(radius),\(lat),\(lon));
          node["amenity"](around:\(radius),\(lat),\(lon));
          node["shop"](around:\(radius),\(lat),\(lon));
          
          // 2. 대규모 구역 포함 여부 확인 (Context)
          is_in(\(lat),\(lon))->.a;
          way.a["amenity"="university"];
          relation.a["amenity"="university"];
          way.a["leisure"="park"];
          relation.a["leisure"="park"];
          way.a["landuse"="campus"];
          relation.a["landuse"="campus"];
        );
        out geom;
        """
        
        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else {
            throw DigitalCaneError.networkError("Invalid Overpass API URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query)".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DigitalCaneError.networkError("Overpass API Error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        do {
            let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
            let buildings = decoded.elements.compactMap { element -> BuildingPolygon? in
                // 1. Way/Relation
                if let geometry = element.geometry, !geometry.isEmpty {
                     let name = element.tags?["name"] ?? element.tags?["name:en"]
                     let points = geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                 
                     var type: BuildingPolygon.ObjectType = .building
                     if element.tags?["amenity"] == "university" || 
                        element.tags?["leisure"] == "park" ||
                        element.tags?["landuse"] == "campus" {
                         type = .area
                     }
                 
                     return BuildingPolygon(id: element.id, name: name ?? "건물", points: points, type: type)
                }
                
                // 2. Node (POI)
                else if element.type == "node", let lat = element.lat, let lon = element.lon {
                    let nameTag = element.tags?["name"] ?? element.tags?["name:en"]
                    let amenity = element.tags?["amenity"]
                    let shop = element.tags?["shop"]
                    
                    guard nameTag != nil || amenity != nil || shop != nil else { return nil }
                    
                    if let amenity = amenity {
                        let blacklist = ["waste_basket", "bench", "waste_disposal", "power_pole", "street_lamp"]
                        if blacklist.contains(amenity) { return nil }
                    }
                    
                    var displayName = nameTag
                    
                    if displayName == nil {
                        if amenity == "parking" { displayName = "주차장" }
                        else if amenity == "toilets" { displayName = "화장실" }
                        else if shop == "convenience" { displayName = "편의점" }
                        else { return nil }
                    }
                    
                    guard let finalName = displayName else { return nil }
                    
                    let offset = 0.00001
                    let points = [
                        CLLocationCoordinate2D(latitude: lat - offset, longitude: lon - offset),
                        CLLocationCoordinate2D(latitude: lat + offset, longitude: lon - offset),
                        CLLocationCoordinate2D(latitude: lat + offset, longitude: lon + offset),
                        CLLocationCoordinate2D(latitude: lat - offset, longitude: lon + offset)
                    ]
                    return BuildingPolygon(id: element.id, name: finalName, points: points, type: .poi)
                }
                
                return nil
            }
            
            print("🏗️ [Overpass] Found \(buildings.count) buildings with geometry.")
            
            // 2. 캐시 저장
            LocationCache.shared.setCachedBuildings(buildings, for: clLocation)
            
            return buildings
            
        } catch {
            print("Overpass Decoding Error: \(error)")
             throw DigitalCaneError.parsingError(error.localizedDescription)
        }
    }
    
    // MARK: - Google Places API (Recall Place Name)
    // Overpass에서 "건물"이라고만 나오고 이름이 없을 때, Google Places API로 이름을 보완
    func fetchNearbyPlaceName(at coordinate: CLLocationCoordinate2D) async throws -> String? {
        guard !googleApiKey.isEmpty else { return nil }
        
        let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(googleApiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.addValue("places.displayName", forHTTPHeaderField: "X-Goog-FieldMask")
        
        let requestBody: [String: Any] = [
            "locationRestriction": [
                "circle": [
                    "center": [
                        "latitude": coordinate.latitude,
                        "longitude": coordinate.longitude
                    ],
                    "radius": 20.0
                ]
            ],
            "maxResultCount": 1,
            "rankPreference": "DISTANCE"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        let decoded = try JSONDecoder().decode(PlacesResponse.self, from: data)
        if let firstPlace = decoded.places?.first, let name = firstPlace.displayName?.text {
            print("🏛️ [Google Places] Found Name: \(name)")
            return name
        }
        
        return nil
    }
    
    // MARK: - 4. Text Search (POI Validation)
    func searchPlaces(query: String) async throws -> [Place] {
        guard !query.isEmpty else { return [] }
        
        guard !googleApiKey.isEmpty else {
            throw DigitalCaneError.missingAPIKey
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
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DigitalCaneError.networkError("Places Search Error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
            
        let decodedResponse = try JSONDecoder().decode(PlacesResponse.self, from: data)
        let places = decodedResponse.places?.compactMap { place -> Place? in
            guard let lat = place.location?.latitude, let lng = place.location?.longitude else { return nil }
            return Place(
                name: place.displayName?.text ?? query,
                address: place.formattedAddress ?? "",
                types: place.types ?? [],
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                isWheelchairAccessible: false
            )
        }
        
        return places ?? []
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

// MARK: - Overpass Data Models
struct OverpassResponse: Codable {
    let elements: [OverpassElement]
}

struct OverpassElement: Codable {
    let type: String
    let id: Int
    let lat: Double? // Node일 경우 존재
    let lon: Double? // Node일 경우 존재
    let tags: [String: String]?
    let geometry: [OverpassGeometry]?
}

struct OverpassGeometry: Codable {
    let lat: Double
    let lon: Double
}

/// 앱 내에서 사용할 간소화된 건물 폴리곤 모델
/// 앱 내에서 사용할 간소화된 건물/POI 폴리곤 모델
struct BuildingPolygon {
    enum ObjectType {
        case building
        case poi
        case area // 대규모 구역 (대학교, 공원 등)
    }
    
    let id: Int
    let name: String
    let points: [CLLocationCoordinate2D]
    let type: ObjectType
}

// MARK: - Data Models (App Internal)

struct LocationIntent: Codable {
    let originName: String? // Optional starting point
    let destinationName: String
    let transportMode: String
    // 대화형 정교화를 위한 필드
    let clarificationNeeded: Bool?
    let clarificationQuestion: String?
    // 사용자 선호 교통수단 (Optional)
    // 사용자 선호 교통수단 (Optional)
    let preferredTransportModes: [String]?
    // 경로 선호 옵션 (LESS_WALKING, FEWER_TRANSFERS)
    let routingPreference: String?
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
    let accessibilityOptions: GAccessibilityOptions? // 접근성 옵션
    let businessStatus: String? // 영업 상태 추가 (OPERATIONAL, CLOSED_TEMPORARILY, CLOSED_PERMANENTLY)
}

struct GAccessibilityOptions: Decodable {
    let wheelchairAccessibleEntrance: Bool?
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
    let isWheelchairAccessible: Bool // 휠체어 접근(턱 없음) 가능 여부
    
    // 기본 생성자 (기존 코드 호환성을 위해 isWheelchairAccessible 기본값 제공)
    init(name: String, address: String, types: [String], coordinate: CLLocationCoordinate2D, isWheelchairAccessible: Bool = false) {
        self.name = name
        self.address = address
        self.types = types
        self.coordinate = coordinate
        self.isWheelchairAccessible = isWheelchairAccessible
    }
    
    var accessibleDescription: String {
        var base = "\(name). \(address)."
        if isWheelchairAccessible {
            base += " 입구에 턱이 없습니다."
        }
        return base
    }
}
