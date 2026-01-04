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
        HelpItem(title: "주변 탐색", 
                 content: """
                 휴대폰이 향하는 방향에 있는 장소를 음성과 진동으로 알려드립니다.
                 현재 어떤 건물이나 상점 안에 있는지도 알 수 있습니다.
                 """, 
                 iconName: "sensor.tag.radiowaves.forward.fill"),
        
        HelpItem(title: "대중교통 안내", 
                 content: """
                 화면 아무 곳이나 길게 누르면서 출발지와 목적지를 말씀해 주세요.
                 출발지를 말하지 않으면 현재 위치에서 출발합니다.
                 '버스로', '환승 적게' 같은 요청도 이해합니다.
                 """, 
                 iconName: "bus.fill"),
        
        HelpItem(title: "도움 요청", 
                 content: """
                 길을 잃거나 도움이 필요할 때, 하단의 'SOS' 탭에서 현재 위치를 확인하거나 보호자에게 문자를 보낼 수 있습니다.
                 """, 
                 iconName: "exclamationmark.triangle.fill"),
                 
        HelpItem(title: "설정", 
                 content: """
                 글자 크기, 음성 속도, 보호자 연락처 등을 설정할 수 있습니다.
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
                    .accessibilityHint("두 번 탭하면 상세 내용을 들을 수 있습니다.")
                }
                
                // 하단 여백
                // 하단 제작자 표시
                VStack(spacing: 5) {
                    Image(systemName: "hand.raised.fill") // 예시 아이콘, 필요시 변경
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("KAIST Assistive AI Lab")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.gray.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .accessibilityHidden(true) // 스크린리더가 굳이 읽을 필요 없는 장식적 요소라면 숨김, 혹은 읽게 할 수도 있음. 여기선 숨김 처리하거나 간단히 읽게 함.
                
                Spacer().frame(height: 50)
            }
            .padding(.horizontal)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
