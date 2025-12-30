import Foundation
import Combine

class NavigationManager: ObservableObject {
    @Published var isNavigating = false
    @Published var isLoading = false // 경로 검색 중 여부
    @Published var currentRouteDescription: String = ""
    @Published var currentStepIndex: Int = 0
    @Published var steps: [RouteStep] = []
    @Published var routeOrigin: String = ""
    @Published var routeDestination: String = ""
    @Published var totalDistance: String = "" // 총 거리 추가
    @Published var totalDuration: String = "" // 총 소요 시간 추가
    
    // 현재 단계의 음성 안내 메시지
    var currentInstruction: String {
        guard currentStepIndex < steps.count else { return "안내가 종료되었습니다." }
        return steps[currentStepIndex].instruction
    }
    
    // 현재 단계의 핵심 행동 (UI 표시용)
    var currentAction: String {
        guard currentStepIndex < steps.count else { return "도착" }
        return steps[currentStepIndex].action
    }
    
    // 현재 단계의 상세 정보
    var currentDetail: String {
        guard currentStepIndex < steps.count else { return "" }
        return steps[currentStepIndex].detail
    }
    
    // 전체 단계 수 (추가됨)
    var totalSteps: Int {
        return steps.count
    }
    
    // 전체 정류장/역 개수 합계 (추가됨)
    var totalTransitStops: Int {
        return steps.reduce(0) { $0 + $1.stopCount }
    }
    
    // API 서비스를 통해 경로를 받아오는 함수
    func findRoute(to userVoiceInput: String, locationManager: LocationManager, onFailure: @escaping (String) -> Void) {
        print("User Voice Input: \(userVoiceInput)")
        
        // 위치 서비스 상태 확인
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            DispatchQueue.main.async {
                onFailure("현재 위치를 확인할 수 없습니다. 설정에서 위치 권한을 확인해 주세요.")
            }
            return
        }
        
        if locationManager.currentLocation == nil {
             DispatchQueue.main.async {
                onFailure("위치 정보를 수신 중입니다. 잠시 후 다시 시도해 주세요.")
            }
            return
        }
        
        isLoading = true
        
        // 1. LLM을 통한 의도 파악
            APIService.shared.analyzeIntent(from: userVoiceInput) { [weak self] intent in
            guard let self = self else { return }
            
            // 1-1. 추가 정보가 필요한 경우 (대화형 정교화)
            if let intent = intent, intent.clarificationNeeded == true, let question = intent.clarificationQuestion {
                print("Clarification needed: \(question)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    onFailure(question)
                }
                return
            }
            
            // 1-2. 의도 파악 실패 혹은 목적지가 없는 경우
            guard let intent = intent, !intent.destinationName.isEmpty else {
                print("Intent analysis failed or empty destination")
                DispatchQueue.main.async {
                    self.isLoading = false
                    onFailure("목적지를 명확히 인식하지 못했습니다. 정확한 장소명을 다시 말씀해 주세요.")
                }
                return
            }
            
            print("Analyzed Intent: Go to \(intent.destinationName) from \(intent.originName ?? "Current")")
            
            // 2. 목적지 검증 (Google Places API)
            APIService.shared.searchPlaces(query: intent.destinationName) { [weak self] foundPlaces in
                guard let self = self else { return }
                guard let places = foundPlaces, !places.isEmpty else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        onFailure("해당 장소를 찾을 수 없습니다. 정확한 이름을 다시 말씀해 주세요.")
                    }
                    return
                }
                
                let bestMatch = places[0]
                let validatedDestination = bestMatch.address.isEmpty ? bestMatch.name : bestMatch.address
                let displayName = bestMatch.name
                
                // 출발지 결정
                let origin = (intent.originName?.isEmpty == false) ? intent.originName! : "Current Location"
                
                // 3. 경로 검색
                APIService.shared.fetchRoute(from: origin, to: validatedDestination, currentLocation: locationManager.currentLocation) { [weak self] routeData in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.isLoading = false
                        if let routeData = routeData {
                            self.startNavigation(with: routeData, origin: origin, destination: displayName)
                        } else {
                            onFailure("해당 목적지로 가는 경로를 찾을 수 없습니다.")
                        }
                    }
                }
            }
        }
    }
    
    private func startNavigation(with routeData: RouteData, origin: String, destination: String) {
        self.steps = routeData.steps
        self.routeOrigin = origin
        self.routeDestination = destination
        self.totalDistance = routeData.totalDistance
        self.totalDuration = routeData.totalDuration
        self.currentRouteDescription = "\(routeData.totalDuration) (\(routeData.totalDistance))"
        self.currentStepIndex = 0
        self.isNavigating = true
    }
    
    func nextStep() {
        if currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
        } else {
            // End of route
            stopNavigation()
        }
    }
    
    func stopNavigation() {
        self.isNavigating = false
        self.steps = []
        self.currentRouteDescription = ""
    }
}
