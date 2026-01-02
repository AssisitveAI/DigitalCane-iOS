import SwiftUI

// MARK: - 도움말 (사용 가이드) 뷰
struct HelpGuideView: View {
    @EnvironmentObject var speechManager: SpeechManager
    
    // 가이드 데이터 모델
    struct HelpItem: Identifiable {
        let id = UUID()
        let title: String
        let content: String
        let iconName: String
    }
    
    let guides = [
        HelpItem(title: "디지털케인 (주변 탐색)", 
                 content: """
                 휴대폰을 들고 몸을 천천히 좌우로 돌리면, 그 방향에 있는 장소를 음성과 진동으로 알려드립니다.
                 주변이 복잡하면 자동으로 탐색 범위를 좁히고, 한적하면 넓힙니다.
                 현재 어떤 건물이나 상점 안에 있는지도 정확히 알려드립니다.
                 """, 
                 iconName: "sensor.tag.radiowaves.forward.fill"),
        
        HelpItem(title: "경로 탐색", 
                 content: """
                 화면을 길게 누른 상태에서 목적지를 말씀해 주세요.
                 '버스로', '환승 적게', '걷기 싫어' 같은 요청도 이해합니다.
                 경로가 준비되면 어떤 옵션이 적용되었는지 음성으로 확인해 드립니다.
                 목적지 부분을 길게 누르면 경로 정보를 복사할 수 있습니다.
                 """, 
                 iconName: "bus.fill"),
        
        HelpItem(title: "도움 요청 (SOS)", 
                 content: """
                 길을 잃었을 때 'SOS' 탭을 선택하세요.
                 위치 버튼을 누르면 현재 주소를 음성으로 들을 수 있고, 문자 버튼을 누르면 보호자에게 위치가 전송됩니다.
                 """, 
                 iconName: "exclamationmark.triangle.fill"),
                 
        HelpItem(title: "설정", 
                 content: """
                 글자 크기, 음성 속도, 탐색 반경 등을 조절할 수 있습니다.
                 보호자 연락처도 여기서 등록해 두세요.
                 """, 
                 iconName: "gearshape.fill")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // 헤더
                Text("사용 설명서")
                    .dynamicFont(size: 34, weight: .bold)
                    .foregroundColor(.yellow)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)
                
                Text("각 항목을 터치하면 상세 설명을 음성으로 들을 수 있습니다.")
                    .dynamicFont(size: 18)
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                // 가이드 목록
                ForEach(guides) { guide in
                    Button(action: {
                        SoundManager.shared.play(.click)
                        speechManager.speak("\(guide.title). \(guide.content)")
                    }) {
                        HStack(alignment: .top, spacing: 15) {
                            Image(systemName: guide.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .foregroundColor(.yellow)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(guide.title)
                                    .dynamicFont(size: 22, weight: .bold)
                                    .foregroundColor(.white)
                                
                                Text(guide.content)
                                    .dynamicFont(size: 17)
                                    .foregroundColor(.gray)
                                    .lineSpacing(4)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(15)
                    }
                    .accessibilityLabel(guide.title)
                    .accessibilityHint(guide.content)
                }
                
                // 하단 여백
                Spacer().frame(height: 50)
            }
            .padding(.horizontal)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
