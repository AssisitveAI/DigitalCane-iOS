import SwiftUI
import CoreLocation

// 도움요청 (SOS) 뷰
struct HelpView: View {
    @EnvironmentObject var speechManager: SpeechManager
    @EnvironmentObject var locationManager: LocationManager // 전역 사용
    @AppStorage("emergencyContact") private var emergencyContact: String = ""
    
    // 유연한 연락처 처리를 위한 상태 변수 제거 (AppStorage 직접 사용)
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 25) {
                Text("도움요청")
                    .dynamicFont(size: 34, weight: .bold)
                    .foregroundColor(.red)
                    .padding(.top, 20)
                
                // --- 연락처 직접 수정 섹션 ---
                VStack(alignment: .leading, spacing: 8) {
                    Text("연락받을 사람 번호")
                        .dynamicFont(size: 18, weight: .bold)
                        .foregroundColor(.yellow)
                    
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.gray)
                        TextField("보호자 번호 입력 (010...)", text: $emergencyContact)
                            .keyboardType(.phonePad)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    Text("입력한 번호는 자동으로 저장되며, 위급 시 이 번호로 문자와 전화가 연결됩니다.")
                        .dynamicFont(size: 14)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("연락처 입력창. 현재 \(emergencyContact) 입력됨.")
                .accessibilityHint("방문할 곳의 사람 번호를 직접 입력할 수 있습니다.")

                Divider().background(Color.gray.opacity(0.3)).padding(.horizontal)

                // 1. 현재 주소 확인
                Button(action: {
                    SoundManager.shared.play(.click)
                    if let address = locationManager.currentAddress {
                        speechManager.speak("현재 위치는 \(address)입니다.")
                    } else {
                        speechManager.speak("현재 위치 정보를 확인하고 있습니다.")
                    }
                }) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text(locationManager.currentAddress ?? "위치 확인 중...")
                            .dynamicFont(size: 20, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)

                // 2. SMS 전송
                Button(action: {
                    SoundManager.shared.play(.click)
                    shareLocation()
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("보호자에게 SMS 전송")
                            .dynamicFont(size: 20, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)

                // 3. 비상 전화
                Button(action: {
                    SoundManager.shared.play(.click)
                    callGuardian()
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("보호자에게 전화")
                            .dynamicFont(size: 20, weight: .bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.bottom, 50)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // AppStorage 사용으로 별도 초기화 불필요
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshHelpView"))) { _ in
             // 탭 진입 시 현재 위치 안내
             if let address = locationManager.currentAddress {
                 speechManager.speak("현재 위치는 \(address)입니다.")
             } else {
                 speechManager.speak("위치 정보를 가져오는 중입니다.")
             }
        }
    }
    
    // 로직 (입력된 번호 기반으로 동작)
    private func shareLocation() {
        if emergencyContact.isEmpty {
            speechManager.speak("연락받을 사람의 번호를 먼저 입력해 주세요.")
            return
        }

        guard let location = locationManager.currentLocation else {
            speechManager.speak("위치 정보를 가져올 수 없습니다.")
            return
        }
        
        let address = locationManager.currentAddress ?? "알 수 없는 위치"
        let mapLink = "https://maps.google.com/maps?q=\(location.coordinate.latitude),\(location.coordinate.longitude)"
        let message = "[디지털케인 긴급 알림]\n내 위치: \(address)\n지도: \(mapLink)"
        
        // 시스템 기본 메시지 앱 호출 (사용자에게 익숙한 환경)
        let phoneNumber = emergencyContact.filter { "0123456789".contains($0) }
        if let encodedBody = message.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics),
           let url = URL(string: "sms:\(phoneNumber)&body=\(encodedBody)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // SMS 불가능한 기기일 경우 대체 공유창
                let activityVC = UIActivityViewController(activityItems: [message], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.present(activityVC, animated: true)
                }
            }
        }
    }
    
    private func callGuardian() {
        if emergencyContact.isEmpty {
            speechManager.speak("연락받을 사람의 번호를 먼저 입력해 주세요.")
            return
        }
        let phoneNumber = emergencyContact.filter { "0123456789".contains($0) }
        if let url = URL(string: "tel://\(phoneNumber)") {
            UIApplication.shared.open(url)
        }
    }
}
