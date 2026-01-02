import SwiftUI
import AVFoundation

// 대기 및 음성 명령 입력 모드 (버튼을 누르고 있으면 듣기)
struct VoiceCommandModeView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var navigationManager: NavigationManager
    var onCommit: (String) -> Void
    
    @State private var isTouching = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 메인 컨텐츠 영역
            VStack(spacing: 30) {
                Spacer()
                
                // 시각적 피드백 (아이콘)
                ZStack {
                    Circle()
                        .stroke(speechManager.isRecording ? Color.red.opacity(0.3) : Color.yellow.opacity(0.2), lineWidth: 2)
                        .scaleEffect(speechManager.isRecording ? 1.5 : 1.0)
                        .opacity(speechManager.isRecording ? 0 : 1)
                        .animation(speechManager.isRecording ? .easeOut(duration: 1.0).repeatForever(autoreverses: false) : .default, value: speechManager.isRecording)

                    Image(systemName: speechManager.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                        .foregroundColor(speechManager.isRecording ? .red : .yellow)
                }
                .accessibilityLabel(speechManager.isRecording ? "듣고 있습니다. 손을 떼면 검색합니다." : "길게 누르고 출발지와 목적지를 말하세요.")
                
                // 안내 텍스트
                Text(speechManager.isRecording ? "듣고 있습니다..." : "출발지와 목적지를 말씀해 주세요. 출발지를 말하지 않으면 현위치를 중심으로 안내합니다.")
                    .dynamicFont(size: 24, weight: .bold)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // 인식된 텍스트 및 로딩 표시
                ZStack {
                    if navigationManager.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                            Text("경로 탐색 중...")
                                .dynamicFont(size: 18)
                                .foregroundColor(.yellow)
                        }
                    } else if !speechManager.transcript.isEmpty {
                        Text("\"\(speechManager.transcript)\"")
                            .dynamicFont(size: 22)
                            .lineLimit(nil)
                            .minimumScaleFactor(0.7)
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(15)
                    }
                }
                .frame(height: 120)
                .padding(.horizontal)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isTouching {
                            isTouching = true
                            startListening()
                        }
                    }
                    .onEnded { _ in
                        isTouching = false
                        stopListeningAndCommit()
                    }
            )
        }
        .background(Color.black)
        .accessibilityAction(.magicTap) {
            if speechManager.isRecording {
                stopListeningAndCommit()
            } else {
                startListening()
            }
        }
    }
    
    private func startListening() {
        if !speechManager.isRecording {
            speechManager.startRecording()
            // 햅틱/사운드 피드백 (통합됨)
            SoundManager.shared.play(.recordingStart)
        }
    }
    
    private func stopListeningAndCommit() {
        if speechManager.isRecording {
            speechManager.stopRecording()
            // 햅틱/사운드 피드백 (통합됨)
            SoundManager.shared.play(.recordingEnd)
            
            if !speechManager.transcript.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onCommit(speechManager.transcript)
                }
            } else {
                speechManager.speak("목소리를 인식하지 못했습니다. 다시 말씀해 주세요.")
            }
        }
    }
}
