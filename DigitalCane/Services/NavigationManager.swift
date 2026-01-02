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
    
    // 현재 경로에 실제로 적용된 탐색 옵션 (음성 피드백용)
    @Published var activeRoutingPreference: String? = nil
    
    // 대화 맥락 유지를 위한 히스토리 (AI가 이전 대화를 기억)
    @Published var conversationHistory: [String] = []
    @Published var isWaitingForClarification = false // 추가 정보 대기 중
    
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
    
    // 대화 히스토리 초기화
    func clearConversation() {
        conversationHistory = []
        isWaitingForClarification = false
    }
    
    // API 서비스를 통해 경로를 받아오는 함수
    func findRoute(to userVoiceInput: String, locationManager: LocationManager, onFailure: @escaping (String) -> Void) {
        print("User Voice Input: \(userVoiceInput)")
        
        // 대화 히스토리에 현재 입력 추가 (Main Thread에서 호출됨을 가정하거나, 안전하게 즉시 추가)
        self.conversationHistory.append("사용자: \(userVoiceInput)")
        
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
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        // 전체 대화 맥락을 포함하여 AI에 전달
        let fullContext = conversationHistory.joined(separator: "\n")
        
        // 1. LLM을 통한 의도 파악 (대화 맥락 포함)
        APIService.shared.analyzeIntent(from: fullContext) { [weak self] intent in
            guard let self = self else { return }
            
            // 1-1. 추가 정보가 필요한 경우 (대화형 정교화)
            if let intent = intent, intent.clarificationNeeded == true, let question = intent.clarificationQuestion {
                print("Clarification needed: \(question)")
                DispatchQueue.main.async {
                    // AI 질문도 히스토리에 추가
                    self.conversationHistory.append("AI: \(question)")
                    self.isWaitingForClarification = true
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
                    self.isWaitingForClarification = true // 추가 정보 요청
                    onFailure("목적지를 명확히 인식하지 못했습니다. 어디로 가고 싶으신가요?")
                }
                return
            }
            
            // 성공적으로 의도 파악 완료
            DispatchQueue.main.async {
                self.isWaitingForClarification = false
            }
            
            print("Analyzed Intent: Go to \(intent.destinationName) from \(intent.originName ?? "Current")")
            
            // 2. 목적지 검증 (Google Places API)
            APIService.shared.searchPlaces(query: intent.destinationName) { [weak self] foundPlaces in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    guard let places = foundPlaces, !places.isEmpty else {
                        self.isLoading = false
                        onFailure("해당 장소를 찾을 수 없습니다. 정확한 이름을 다시 말씀해 주세요.")
                        return
                    }
                    
                    let bestMatch = places[0]
                    let validatedDestination = bestMatch.address.isEmpty ? bestMatch.name : bestMatch.address
                    let displayName = bestMatch.name
                    
                    // 출발지 결정
                    let origin = (intent.originName?.isEmpty == false) ? intent.originName! : "Current Location"
                    
                    let preferredModes = intent.preferredTransportModes
                    let routingPreference = intent.routingPreference
                    
                    APIService.shared.fetchRoute(from: origin, 
                                                 to: validatedDestination, 
                                                 currentLocation: locationManager.currentLocation,
                                                 preferredModes: preferredModes,
                                                 routingPreference: routingPreference) { [weak self] routeData, isFallbackApplied in
                        guard let self = self else { return }
                        
                        DispatchQueue.main.async {
                            self.isLoading = false
                            if let routeData = routeData {
                                // 실제 적용된 옵션 저장 (우선순위: Intent -> Settings -> nil)
                                // 빈 문자열("")도 nil처럼 취급하여 설정값이 무시되지 않도록 함
                                var appliedPref: String? = nil
                                if let intentPref = routingPreference, !intentPref.isEmpty {
                                    appliedPref = intentPref
                                }
                                
                                if appliedPref == nil {
                                    // Intent가 없으면 설정값을 확인하여 무엇이 적용되었는지 추적
                                    if UserDefaults.standard.bool(forKey: "preferLessWalking") {
                                        appliedPref = "LESS_WALKING"
                                    } else if UserDefaults.standard.bool(forKey: "preferFewerTransfers") {
                                        appliedPref = "FEWER_TRANSFERS"
                                    }
                                }
                                self.activeRoutingPreference = appliedPref
                                
                                self.startNavigation(with: routeData, 
                                                     origin: origin, 
                                                     destination: displayName, 
                                                     isFallback: isFallbackApplied)
                            } else {
                                let modeNames = (preferredModes ?? []).joined(separator: ", ")
                                let failMsg = preferredModes != nil 
                                    ? "요청하신 \(modeNames) 경로를 찾을 수 없습니다." 
                                    : "해당 목적지로 가는 경로를 찾을 수 없습니다."
                                onFailure(failMsg)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func startNavigation(with routeData: RouteData, origin: String, destination: String, isFallback: Bool = false) {
        var finalSteps = routeData.steps
        
        // Fallback 발생 시 첫 번째 단계 안내에 멘트 추가
        if isFallback, !finalSteps.isEmpty {
            let originalInstr = finalSteps[0].instruction
            finalSteps[0] = RouteStep(
                type: finalSteps[0].type,
                instruction: "요청하신 교통수단으로 이동이 어려워, 최적 경로로 안내합니다. " + originalInstr, // 안내 멘트 결합
                detail: finalSteps[0].detail,
                action: finalSteps[0].action,
                stopCount: finalSteps[0].stopCount,
                duration: finalSteps[0].duration,
                distance: finalSteps[0].distance,
                vehicleType: finalSteps[0].vehicleType
            )
        }
        
        self.steps = finalSteps
        self.routeOrigin = origin
        self.routeDestination = destination
        self.totalDistance = routeData.totalDistance
        self.totalDuration = routeData.totalDuration
        self.currentRouteDescription = "\(routeData.totalDuration) (\(routeData.totalDistance))"
        self.currentStepIndex = 0
        self.isNavigating = true
        // 경로 검색 성공 - 대화 맥락 초기화 (새 검색은 새 대화로)
        clearConversation()
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
        self.routeOrigin = ""
        self.routeDestination = ""
        self.totalDistance = ""
        self.totalDuration = ""
        self.currentStepIndex = 0
        // 대화 맥락 초기화 (탭 전환 시)
        clearConversation()
    }
}
