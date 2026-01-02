import Foundation
import Speech
import AVFoundation
import SwiftUI
import AudioToolbox

class SpeechManager: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var permissionGranted = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    // 권한 요청
    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    self.permissionGranted = true
                default:
                    self.permissionGranted = false
                    print("Speech recognition permission denied")
                }
            }
        }
    }
    
    // 말하기 즉시 중단
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // TTS 말하기
    // interrupt: true이면 즉시 중단하고 말하기(기본값), false이면 이어서 말하기
    func speak(_ text: String, interrupt: Bool = true) {
        // VoiceOver가 활성화되어 있으면 앱 TTS 사용 안 함 (충돌 방지)
        // VoiceOver가 이미 화면 요소를 읽어주므로 중복 발화 방지
        if UIAccessibility.isVoiceOverRunning {
            // VoiceOver 사용자에게는 accessibilityAnnouncement로 전달
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        
        if interrupt {
            stopSpeaking() // 기존 발화 중단 후 새로운 발화
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        
        // Quick Win 2: 사용자 설정에 따른 TTS 속도 적용
        let savedRate = UserDefaults.standard.float(forKey: "speechRate")
        utterance.rate = savedRate > 0 ? savedRate : 0.5 // 기본값 0.5
        
        // 오디오 세션 설정
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // .voiceChat 모드가 시스템 안정성이 높음
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers, .defaultToSpeaker])
            // 세션이 이미 활성화되어 있는지 확인하거나, 안전하게 활성화 시도
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            }
        } catch {
            print("⚠️ Audio Session Setup Error in Speak (Safe): \(error.localizedDescription)")
        }
        
        synthesizer.speak(utterance)
    }
    
    // 시스템 효과음 재생 헬퍼
    private func playSound(_ systemSoundID: SystemSoundID) {
        AudioServicesPlaySystemSound(systemSoundID)
    }
    
    // 녹음 시작
    func startRecording() {
        guard permissionGranted else {
            speak("마이크 권한이 필요합니다. 설정에서 허용해 주세요.")
            return
        }
        
        // 듣기 시작 효과음 (Begin Record)
        playSound(1113)
        
        // 말하기 중단
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // 이전 작업 정리
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // .voiceChat 모드는 시스템 오디오 엔진과 버퍼 처리가 더 부드럽고 호환성이 높음
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session Setup Error: \(error)")
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create request") }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString // 인식된 텍스트 업데이트
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                // 내부 호출이 아닌 경우에만 stopRecording 호출 (무한 루프 방지)
                if self.isRecording { self.stopRecording() }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // 버퍼 사이즈를 4096으로 상향하여 하드웨어 경고 로그(mDataByteSize 0) 발생 빈도 감소
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { (buffer, when) in
            // 데이터 유무를 엄격히 체크
            if buffer.frameLength > 0, 
               let data = buffer.audioBufferList.pointee.mBuffers.mData,
               buffer.audioBufferList.pointee.mBuffers.mDataByteSize > 0 {
                self.recognitionRequest?.append(buffer)
            }
        }
        
        // 안전한 엔진 재시작: 이미 실행 중이면 중지 후 시작 (버퍼 충돌 방지)
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            transcript = "" 
            print("🎙️ Audio Engine Started Successfully")
            
            // 시작 햅틱 피드백
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("❌ Audio Engine Start Error: \(error.localizedDescription)")
        }
    }
    
    // 녹음 중지
    func stopRecording() {
        if isRecording {
            audioEngine.stop()
            inputNodeRemoveTap()
            recognitionRequest?.endAudio()
            isRecording = false
            
            // 종료 효과음 (End Record)
            playSound(1114)
            
            print("Final Transcript: \(self.transcript)")
        }
    }
    
    private func inputNodeRemoveTap() {
        // 탭 제거 시 안전 장치
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
    }
}

// 사운드 매니저 (UI 피드백 통합: 사운드 + 햅틱)
class SoundManager {
    static let shared = SoundManager()
    
    private init() {
        // 햅틱 엔진 사전 준비 (지연 최소화)
        prepareHapticGenerators()
    }
    
    // 사전 준비된 햅틱 제너레이터들 (성능 최적화)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private func prepareHapticGenerators() {
        heavyGenerator.prepare()
        rigidGenerator.prepare()
        softGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    enum SoundType {
        case click          // 일반 클릭
        case tabSelection   // 탭 변경
        case recordingStart // 녹음 시작
        case recordingEnd   // 녹음 종료
        case success        // 성공 (경로/장소 발견)
        case failure        // 실패/에러
        case finding        // 탐색 중 (방향 감지) - 가장 중요!
    }
    
    func play(_ type: SoundType) {
        // 1. 사운드 재생 (부드럽고 명확한 시스템 사운드)
        var soundID: SystemSoundID = 0
        switch type {
        case .click:          soundID = 1104  // Tock (부드러운 클릭)
        case .tabSelection:   soundID = 1103  // Tink (가벼운 탭)
        case .recordingStart: soundID = 1113  // Begin Recording (표준)
        case .recordingEnd:   soundID = 1114  // End Recording (표준)
        case .success:        soundID = 1001  // Mail Sent (부드러운 성공)
        case .failure:        soundID = 1053  // 부드러운 알림음
        case .finding:        soundID = 1104  // Tock (부드럽지만 명확)
        }
        AudioServicesPlaySystemSound(soundID)
        
        // 2. 강화된 햅틱 피드백
        let hapticBlock = { [self] in
            switch type {
            case .click:
                // 클릭: Heavy (강함)
                heavyGenerator.impactOccurred(intensity: 0.8)
                
            case .tabSelection:
                // 탭 변경: Heavy + 약간 뒤에 Soft (이중 햅틱)
                heavyGenerator.impactOccurred(intensity: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
                    softGenerator.impactOccurred(intensity: 0.6)
                }
                
            case .success:
                // 성공: Success 알림 + Heavy (이중 피드백)
                notificationGenerator.notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                    heavyGenerator.impactOccurred(intensity: 1.0)
                }
                
            case .failure:
                // 실패: Error 알림 (강한 경고)
                notificationGenerator.notificationOccurred(.error)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                    notificationGenerator.notificationOccurred(.error)
                }
                
            case .recordingStart:
                // 녹음 시작: Heavy + Rigid (강력한 시작 신호)
                heavyGenerator.impactOccurred(intensity: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                    rigidGenerator.impactOccurred(intensity: 1.0)
                }
                
            case .recordingEnd:
                // 녹음 종료: Rigid x2 (확실한 종료 신호)
                rigidGenerator.impactOccurred(intensity: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
                    rigidGenerator.impactOccurred(intensity: 0.8)
                }
                
            case .finding:
                // 🔥 디지털케인 탐색: 가장 강력한 3단 햅틱 (확실한 인지!)
                heavyGenerator.impactOccurred(intensity: 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
                    rigidGenerator.impactOccurred(intensity: 1.0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [self] in
                    heavyGenerator.impactOccurred(intensity: 0.9)
                }
            }
            
            // 다음 호출을 위해 제너레이터 준비 (지연 최소화)
            prepareHapticGenerators()
        }
        
        if Thread.isMainThread {
            hapticBlock()
        } else {
            DispatchQueue.main.async(execute: hapticBlock)
        }
    }
}
