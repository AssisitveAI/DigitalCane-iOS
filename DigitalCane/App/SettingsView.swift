import SwiftUI

// 설정 뷰
struct SettingsView: View {
    @AppStorage("preferLessWalking") private var preferLessWalking: Bool = false
    @AppStorage("preferFewerTransfers") private var preferFewerTransfers: Bool = false
    @AppStorage("defaultSearchRadius") private var searchRadius: Double = 200.0
    @AppStorage("fontScale") private var fontScale: Double = 1.0
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    @AppStorage("speechRate") private var speechRate: Double = 0.5 // Quick Win 2: TTS 속도 설정
    
    // Quick Win 2: 속도를 사람이 읽을 수 있는 텍스트로 변환
    private var speechRateDescription: String {
        if speechRate < 0.4 { return "느리게" }
        else if speechRate < 0.55 { return "보통" }
        else { return "빠르게" }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("화면 설정")) {
                    VStack(alignment: .leading) {
                        Text("글자 크기: \(String(format: "%.1f", fontScale))배")
                            .dynamicFont(size: 18, weight: .bold)
                        
                        Slider(value: $fontScale, in: 0.8...2.0, step: 0.1)
                            .accentColor(.yellow)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("글자 크기 조절")
                    .accessibilityValue("\(Int(fontScale * 100))퍼센트")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if fontScale < 2.0 { fontScale += 0.1 }
                        case .decrement:
                            if fontScale > 0.8 { fontScale -= 0.1 }
                        default: break
                        }
                    }
                    
                    // Quick Win 2: TTS 속도 설정
                    VStack(alignment: .leading) {
                        Text("음성 안내 속도: \(speechRateDescription)")
                            .dynamicFont(size: 18, weight: .bold)
                        
                        Slider(value: $speechRate, in: 0.3...0.7, step: 0.05)
                            .accentColor(.yellow)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("음성 안내 속도 조절")
                    .accessibilityValue(speechRateDescription)
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if speechRate < 0.7 { speechRate += 0.05 }
                        case .decrement:
                            if speechRate > 0.3 { speechRate -= 0.05 }
                        default: break
                        }
                    }
                }
                
                Section(header: Text("경로 탐색 설정")) {
                    Toggle(isOn: $preferLessWalking) {
                        VStack(alignment: .leading) {
                            Text("안전 우선 (도보 최소화)")
                                .dynamicFont(size: 18, weight: .bold)
                            Text(preferLessWalking ? "걷는 거리가 적은 경로를 우선합니다.\n(소요 시간이 더 걸릴 수 있습니다)" : "최단 시간 경로를 우선합니다.")
                                .dynamicFont(size: 14)
                                .foregroundColor(.gray)
                        }
                    }
                    .accessibilityHint("켜면 걷는 거리를 줄이는 경로를, 끄면 시간이 가장 적게 걸리는 경로를 찾습니다.")
                    
                    Toggle(isOn: $preferFewerTransfers) {
                        VStack(alignment: .leading) {
                            Text("환승 최소화")
                                .dynamicFont(size: 18, weight: .bold)
                            Text(preferFewerTransfers ? "갈아타는 횟수가 적은 경로를 우선합니다." : "빠른 경로를 우선합니다.")
                                .dynamicFont(size: 14)
                                .foregroundColor(.gray)
                        }
                    }
                    .accessibilityHint("켜면 갈아타는 횟수를 줄이는 경로를 찾습니다.")
                }
                
                Section(header: Text("디지털케인 설정")) {
                    VStack(alignment: .leading) {
                        Text("기본 탐색 반경: \(Int(searchRadius))m")
                            .dynamicFont(size: 18)
                        Slider(value: $searchRadius, in: 20...500, step: 10)
                            .accentColor(.yellow)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("탐색 반경 설정")
                    .accessibilityValue("\(Int(searchRadius)) 미터")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            if searchRadius < 500 { searchRadius += 10 }
                        case .decrement:
                            if searchRadius > 20 { searchRadius -= 10 }
                        default: break
                        }
                    }
                }
                
                Section(header: Text("SOS 설정")) {
                    VStack(alignment: .leading) {
                        Text("비상 연락처 (보호자)")
                            .dynamicFont(size: 18, weight: .bold)
                        TextField("전화번호 입력 (- 없이)", text: $emergencyContact)
                            .keyboardType(.phonePad)
                            .foregroundColor(.black) // Form 내에서는 기본 색상 사용
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("비상 연락처 입력")
                    .accessibilityValue(emergencyContact.isEmpty ? "비어있음" : emergencyContact)
                }
                
                Section(footer: 
                    VStack(spacing: 8) {
                        Text("Made with ❤️ by")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text("KAIST Assistive AI Lab")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("제작: 카이스트 보조 인공지능 연구실")
                ) {
                    HStack {
                        Text("버전").dynamicFont(size: 16)
                        Spacer()
                        Text("1.0.0").dynamicFont(size: 16)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("설정")
            .onTapGesture {
                hideKeyboard()
            }
        }
    }
}
