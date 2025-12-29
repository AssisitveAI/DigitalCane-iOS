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
        
        // 오디오 세션 설정 (재생 모드 -> playAndRecord로 통일하여 전환 시 크래시 방지)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 녹음과 재생을 빈번하게 오가므로 세션 카테고리를 고정
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio Session Setup Error in Speak: \(error)")
        }
        
        synthesizer.speak(utterance)
    }
    
    // 녹음 시작
    func startRecording() {
        guard permissionGranted else { return }
        
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
            // 녹음 및 재생 모드, 스피커 출력 강제
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
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
                self.stopRecording()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            // 빈 버퍼가 들어오면 크래시가 발생할 수 있으므로 체크 (mDataByteSize error fix)
            if buffer.frameLength > 0 {
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
        audioEngine.stop()
        inputNodeRemoveTap()
        recognitionRequest?.endAudio()
        isRecording = false
        
        print("Final Transcript: \(self.transcript)")
    }
    
    private func inputNodeRemoveTap() {
        // 탭 제거 시 안전 장치
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
    }
}
