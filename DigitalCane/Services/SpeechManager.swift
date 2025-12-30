import Foundation
import Speech
import AVFoundation
import SwiftUI

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
        if interrupt {
            stopSpeaking() // 기존 발화 중단 후 새로운 발화
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.5
        
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
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            // 초기화
            transcript = "" 
        } catch {
            print("Audio Engine Start Error: \(error)")
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
