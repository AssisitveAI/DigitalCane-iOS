import CoreHaptics
import UIKit

class HapticManager: ObservableObject {
    private var engine: CHHapticEngine?
    
    init() {
        prepare()
    }
    
    /// 햅틱 엔진 초기화 및 준비
    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            
            // 엔진이 중단되었을 때(백그라운드 등) 재시작 핸들러
            engine?.stoppedHandler = { reason in
                print("Haptic Engine Stopped: \(reason)")
                do {
                    try self.engine?.start()
                } catch {
                    print("Failed to restart Haptic Engine: \(error)")
                }
            }
            
            // 햅틱 서버 재설정 핸들러 (오디오 세션 인터럽트 등)
            engine?.resetHandler = { [weak self] in
                print("Haptic Engine Reset")
                do {
                    try self?.engine?.start()
                } catch {
                    print("Failed to restart Haptic Engine After Reset: \(error)")
                }
            }
            
        } catch {
            print("Haptic Engine Creation Error: \(error)")
        }
    }
    
    /// 거리에 따른 동적 햅틱 피드백 재생
    /// - Parameter distance: 목표 장소까지의 거리 (미터)
    func playDistanceHaptic(distance: Double) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        // 1. 거리별 파라미터 매핑 (거리가 가까울수록 강하고, 멀수록 약하게)
        // 최대 감지 거리: 약 50m (그 이상은 약한 진동 유지)
        var intensity: Float = 0.5
        var sharpness: Float = 0.5
        var duration: Double = 0.1
        
        if distance < 10.0 {
            // 매우 가까움 (충돌 주의): 강하고 묵직한 진동 (Thud-like)
            intensity = 1.0
            sharpness = 0.2 // 둔탁함
            duration = 0.15
        } else if distance < 30.0 {
            // 중간 거리: 뚜렷하고 선명한 진동 (Tap-like)
            intensity = 0.7
            sharpness = 0.6
            duration = 0.1
        } else {
            // 먼 거리: 가볍고 톡톡 튀는 진동 (Tick-like)
            intensity = 0.4
            sharpness = 0.8 // 날카로움
            duration = 0.05
        }
        
        // 2. 햅틱 이벤트 생성
        // Transient: 단타성 진동 (톡, 툭)
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: 0, duration: duration)
        
        // 3. 패턴 실행
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
}
