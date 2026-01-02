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
                 • 탐색 방법: 휴대폰을 세워 마치 사진을 찍듯 잡아주세요. 그 상태로 천천히 몸을 좌우로 돌리며 주변을 비추면, 휴대폰이 향하는 방향에 있는 장소를 정확히 알려줍니다.
                 • 스마트 반경 조절: 주변 장소가 많으면 혼란을 줄이기 위해 범위를 좁히고, 장소가 적으면 범위를 넓혀 정보를 찾습니다. (기본 설정)
                   - 팁 1: 슬라이더를 직접 움직이면 언제든지 수동 모드로 바뀌어 원하는 거리로 설정할 수 있습니다.
                   - 팁 2: 앱을 껐다 켜면 다시 스마트 모드가 자동으로 켜져 최적의 설정을 도와줍니다.
                 • 정밀 위치 안내: 현재 내가 어떤 건물에 있는지, 혹은 편의점 입구 바로 앞에 도착했는지까지 구분하여 알려줍니다.
                 • 똑똑한 정보 선별: 이동에 꼭 필요한 정보만 앱이 알아서 골라줍니다. 주차장이나 화장실처럼 유용한 장소는 안내하고, 불확실하거나 사소한 정보는 생략하여 혼란을 줄입니다.
                 • 휠체어 이용자를 위해 입구가 편리한 곳은 별도로 안내해 드립니다.
                 """, 
                 iconName: "sensor.tag.radiowaves.forward.fill"),
        
        HelpItem(title: "대중교통 경로 안내 (내비게이션)", 
                 content: "화면 아무 곳이나 손가락으로 길게 누른 상태에서 목적지를 말씀해 주세요. '버스로 가고 싶어'나 '지하철로 최단 시간'처럼 구체적으로 요청하시면 선호하는 수단으로 맞춤 경로를 찾아드립니다. 출발 전, 외출 준비를 돕기 위해 현재 날씨와 기온 정보도 브리핑해 드립니다.", 
                 iconName: "bus.fill"),
        
        HelpItem(title: "도움 요청 (SOS)", 
                 content: "위급한 상황이나 길을 잃었을 때 이 탭을 사용하세요. 사전에 등록된 보호자에게 현재 정확한 위치와 지도 링크를 문자로 즉시 전송하며, 필요 시 바로 전화를 연결할 수 있습니다.", 
                 iconName: "exclamationmark.triangle.fill"),
                 
        HelpItem(title: "설정 및 개인화", 
                 content: "저시력 사용자를 위해 글자 크기를 조절하거나, 주변 탐색 반경을 내 보행 속도에 맞춰 변경할 수 있습니다. 또한, 위급 상황 시 연락할 보호자 번호를 미리 등록할 수 있습니다.", 
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
