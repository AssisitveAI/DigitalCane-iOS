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
                 • 카메라 모드 탐색: 휴대폰을 세워 정면을 비추세요. 마치 사진을 찍듯 탐색하면 더 정확하고 팔도 편안합니다.
                 • 스마트 반경 조절: 번화가에선 범위를 좁히고, 한적한 곳에선 넓혀서 가장 적절한 장소를 자동으로 찾아줍니다. (기본 설정)
                   - 팁: 슬라이더를 직접 움직이면 언제든지 수동 모드로 바뀌어 원하는 거리로 설정할 수 있습니다.
                 • 정밀 위치 안내: 건물의 내부는 물론, 편의점 바로 앞까지 정확하게 구분하여 알려줍니다.
                 • 똑똑한 골라 듣기: 가로등이나 쓰레기통 같은 불필요한 정보는 거르고, 주차장이나 화장실처럼 꼭 필요한 정보만 쏙쏙 안내합니다.
                 • 휠체어 이용자를 위해 입구가 편리한 곳은 별도로 안내해 드립니다.
                 """, 
                 iconName: "sensor.tag.radiowaves.forward.fill"),
        
        HelpItem(title: "대중교통 경로 안내 (내비게이션)", 
                 content: "화면에 손을 대고 있는 상태에서 목적지를 말씀해 주세요. '버스로 가고 싶어'나 '지하철로 최단 시간'처럼 구체적으로 요청하시면 선호하는 수단으로 맞춤 경로를 찾아드립니다. 출발 전, 외출 준비를 돕기 위해 현재 날씨와 기온 정보도 브리핑해 드립니다.", 
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
