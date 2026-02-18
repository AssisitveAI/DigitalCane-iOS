import Foundation
import CoreLocation

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
    
    private var openAIApiKey: String {
        guard let filePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: filePath),
              let value = plist["OPENAI_API_KEY"] as? String else {
            print("⚠️ Error: OPENAI_API_KEY not found in Secrets.plist")
            return ""
        }
        return value
    }
    
    // MARK: - 1. Intent Analysis using OpenAI
    func analyzeIntent(from text: String, completion: @escaping (LocationIntent?) -> Void) {
        guard !openAIApiKey.isEmpty else {
            print("OpenAI API Key is missing")
            completion(nil)
            return
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // JSON Body
        let systemPrompt = """
        You are a smart mobility assistant for a visually impaired user (Digital Cane).
        The user may ask "How do I get to...?", "Guide me to...", or simply "Go to...".
        Your task is to extract the EXACT 'destinationName' and optionally 'originName' regardless of the phrasing.
        
        CRITICAL RULES:
        1. Extract names exactly as spoken. Do not guess or hallucinate.
        2. If the user does not specify a destination, set "destinationName" to "".
        3. If the user specifies a starting point (e.g., "From Seoul Station to Busan"), set "originName" to that place. Otherwise, set "originName" to "".
        4. Default "transportMode" to "TRANSIT".
        5. If the request is ambiguous (e.g., distinguishing "Sin-chon" as Train Station vs Subway, or "Gangnam" as Station vs Area), set "clarificationNeeded" to true and provide a specific Korean question in "clarificationQuestion" (e.g., "신촌역 기차역으로 갈까요, 지하철역으로 갈까요?").
        6. If the input is unintelligible or irrelevant, set "clarificationNeeded" to true and ask "잘 못 들었습니다. 목적지를 다시 말씀해 주시겠어요?" in "clarificationQuestion".
        7. Context Inference: You may infer the specific location from context (e.g. 'Seoul School' -> 'Seoul City Hall'), BUT if multiple candidates exist (e.g. 'Terminal' in Seoul has Gangnam/Dong Seoul/Nambu), DO NOT GUESS. Set "clarificationNeeded" to true and ask "어느 터미널로 갈까요?" in "clarificationQuestion".
        
        Examples:
        - User: "Go to Seoul Station" -> {"destinationName": "서울역", "originName": "", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        - User: "From Gangnam to Coex" -> {"destinationName": "코엑스", "originName": "강남", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        - User: "From Seoul School for the Blind to City Hall" -> {"destinationName": "Seoul City Hall", "originName": "Seoul School for the Blind", "transportMode": "TRANSIT", "clarificationNeeded": false, "clarificationQuestion": null}
        
        Respond ONLY in JSON format.
        """
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o", // gpt-5.2 접근 권한 오류로 인해 안정적인 gpt-4o로 복구
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "response_format": ["type": "json_object"]
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
                print("OpenAI Network Error: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
                if let content = decodedResponse.choices.first?.message.content,
                   let data = content.data(using: .utf8) {
                    print("🤖 OpenAI Raw JSON: \(content)")
                    
                    if let intent = try? JSONDecoder().decode(LocationIntent.self, from: data) {
                        completion(intent)
                    } else {
                        print("Failed to parse OpenAI Content")
                        completion(nil)
                    }
                } else {
                    print("No content in OpenAI response")
                    completion(nil)
                }
            } catch {
                print("OpenAI Decoding Error: \(error)")
                if let str = String(data: data, encoding: .utf8) {
                    print("Raw Res: \(str)")
                }
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - 2. Google Routes API
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
             // 좌표가 없으면 Fallback
             originBody = ["address": "서울역"]
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
                // 디버깅용 출력
                // if let str = String(data: data, encoding: .utf8) { print("Routes Res: \(str)") }
                
                let decodedResponse = try JSONDecoder().decode(GRouteResponse.self, from: data)
                if let route = decodedResponse.routes?.first,
                   let leg = route.legs?.first {
                    
                    // GRouteStep -> RouteStep 변환
                    let steps = (leg.steps ?? []).compactMap { self.convertStep($0) }
                    let totalDuration = "약 \((Int(leg.duration?.replacingOccurrences(of: "s", with: "") ?? "0") ?? 0) / 60)분"
                    
                    let routeData = RouteData(steps: steps, totalDuration: totalDuration)
                    completion(routeData)
                } else {
                    print("No routes found")
                    completion(nil)
                }
            } catch {
                print("Google Routes Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - 3. Nearby Places Search (Google Places API v1)
    // MARK: - 3. Nearby Places Search (Google Places API v1)
    func fetchNearbyPlaces(latitude: Double, longitude: Double, radius: Double, completion: @escaping ([Place]?, String?) -> Void) {
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
                completion(nil, "네트워크 오류가 발생했습니다.")
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
                completion(nil)
                return
            }
            
            do {
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
                print("Search Places Decoding Error: \(error)")
                completion(nil)
            }
        }.resume()
    }

    // Google API Step -> App RouteStep 변환 로직
    private func convertStep(_ gStep: GRouteStep) -> RouteStep? {
        // 도보 경로는 제외 (사용자 요청: 정류장/역 이름, 버스 번호 등만 제공)
        if gStep.travelMode == "WALK" {
            return nil
        }
        
        let detail = gStep.localizedValues?.duration?.text ?? ""
        var type: StepType = .ride
        var action = "이동"
        var instruction = gStep.navigationInstruction?.instructions ?? "이동"
        var stopCount = 0
        
        if let mode = gStep.travelMode, mode == "TRANSIT", let transit = gStep.transitDetails {
            type = .ride
            let line = transit.transitLine?.name ?? transit.transitLine?.shortName ?? "버스/지하철"
            let departure = transit.stopDetails?.departureStop?.name ?? "출발지"
            let arrival = transit.stopDetails?.arrivalStop?.name ?? "도착지"
            let headsign = transit.headsign ?? ""
            stopCount = transit.stopCount ?? 0
            
            // 디테일한 정보 조합 (개선됨: "강남역에서 교대 방면 2호선을 타고...")
            let directionInfo = headsign.isEmpty ? "" : "\(headsign) 방면 "
            action = "\(line) 탑승"
            instruction = "\(departure)에서 \(directionInfo)\(line)을 타고, \(arrival)에 내리세요."
            
            return RouteStep(type: .board,
                             instruction: instruction,
                             detail: "이동 시간 약 \(detail), \(stopCount)개 정류장을 이동합니다.",
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

// MARK: - OpenAI Codable Models

struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Decodable {
    let message: OpenAIMessage
}

struct OpenAIMessage: Decodable {
    let content: String
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
