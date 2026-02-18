import Foundation
import CoreHaptics
import UIKit

/// 햅틱 엔진을 관리하고 다양한 진동 패턴을 제공하는 서비스
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
            
            // 엔진이 중단되었을 때 재시작 핸들러
            engine?.stoppedHandler = { reason in
                print("Haptic Engine Stopped: \(reason)")
                do {
                    try self.engine?.start()
                } catch {
                    print("Failed to restart Haptic Engine: \(error)")
                }
            }
            
            // 햅틱 서버 재설정 핸들러
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
    
    /// 장소 유형에 따른 특화된 햅틱 패턴 재생
    func playPatternForPlace(_ place: Place, distance: Double) {
        let types = place.types
        
        if types.contains("crosswalk") || types.contains("intersection") || place.name.contains("횡단보도") {
            // 1. 교차로/횡단보도: 매우 뚜렷하고 연속적인 경고형 진동
            playWarningHaptic()
        } else if types.contains("transit_station") || types.contains("bus_stop") || place.name.contains("역") || place.name.contains("정류장") {
            // 2. 대중교통: 짧고 경쾌한 2단 진동 (알림 스타일)
            playTransitHaptic()
        } else {
            // 3. 일반 장소: 거리에 따른 동적 진동 (기존 로직)
            playDistanceHaptic(distance: distance)
        }
    }
    
    /// 거리에 따른 동적 햅틱 피드백 (기존 로직 유지)
    func playDistanceHaptic(distance: Double) {
        guard let engine = engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        var intensity: Float = 0.5
        var sharpness: Float = 0.5
        
        if distance < 10.0 {
            intensity = 1.0
            sharpness = 0.3
        } else if distance < 30.0 {
            intensity = 0.7
            sharpness = 0.6
        } else {
            intensity = 0.4
            sharpness = 0.8
        }
        
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: 0)
        
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play distance haptic: \(error)")
        }
    }
    
    /// 횡단보도/위험 요소용 패턴 (연속 진동)
    private func playWarningHaptic() {
        guard let engine = engine else { return }
        
        // 3번의 강한 Transient 진동
        var events = [CHHapticEvent]()
        for i in 0..<3 {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: Double(i) * 0.1)
            events.append(event)
        }
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play warning haptic: \(error)")
        }
    }
    
    /// 대중교통용 패턴 (2단 알림)
    private func playTransitHaptic() {
        guard let engine = engine else { return }
        
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ], relativeTime: 0.15)
        ]
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play transit haptic: \(error)")
        }
    }
}
