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
                 앞을 향해 서서 휴대폰을 가슴 높이로 똑바로 들어주세요. 그 상태로 천천히 몸을 좌우로 돌리면, 휴대폰이 가리키는 방향에 있는 장소를 음성과 진동으로 알려드립니다.
                 앱이 자동으로 주변의 장소 밀도를 파악합니다. 번화가에서는 가까운 곳만 안내하고, 한적한 곳에서는 더 넓은 범위를 탐색합니다. 슬라이더를 직접 조절하면 수동 모드로 전환되며, 앱을 다시 시작하면 자동 모드로 복귀합니다.
                 GPS보다 정밀하게, 현재 어떤 건물이나 상점 안에 있는지 이름으로 정확히 알려드립니다. 주차장, 화장실 등 유용한 시설은 안내하고, 가로등 같은 불필요한 정보는 생략합니다.
                 휠체어 이용이 편리한 입구가 있는 곳은 별도로 안내해 드립니다.
                 """, 
                 iconName: "sensor.tag.radiowaves.forward.fill"),
        
        HelpItem(title: "대중교통 경로 안내", 
                 content: """
                 화면 아무 곳이나 손가락으로 길게 누른 상태에서 목적지를 말씀해 주세요. 출발지를 말하지 않으면 현재 위치에서 출발합니다.
                 '버스로 가줘', '지하철만 탈래', '환승 적게', '걷기 싫어' 같은 요청도 이해합니다.
                 경로가 준비되면, 앱이 어떤 교통수단과 옵션을 적용했는지 음성으로 확인해 드립니다. 예를 들어 "요청하신 버스 경로 중 환승이 가장 적은 경로로 안내합니다"라고 말씀드립니다.
                 경로 안내 화면에서 목적지 이름 부분을 길게 누르면, 경로 정보가 복사되어 카카오톡 등으로 공유할 수 있습니다.
                 출발 전 현재 날씨와 기온 정보도 함께 브리핑해 드립니다.
                 """, 
                 iconName: "bus.fill"),
        
        HelpItem(title: "도움 요청 (SOS)", 
                 content: """
                 위급하거나 길을 잃었을 때 사용하세요. 화면 하단에서 'SOS' 탭을 선택하면 됩니다.
                 화면 상단의 위치 버튼을 누르면 현재 주소와 가까운 건물 정보를 음성으로 들을 수 있습니다.
                 문자 보내기 버튼을 누르면, 입력된 보호자 번호로 현재 위치 주소와 구글 지도 링크가 포함된 긴급 문자가 발송됩니다.
                 전화 버튼을 누르면 바로 통화가 연결됩니다.
                 보호자 번호는 설정에서 미리 등록하거나, SOS 화면에서 바로 수정할 수도 있습니다.
                 """, 
                 iconName: "exclamationmark.triangle.fill"),
                 
        HelpItem(title: "설정 및 개인화", 
                 content: """
                 글자가 작게 느껴지면 '글자 크기' 설정으로 최대 2배까지 키울 수 있습니다.
                 음성 안내가 너무 빠르거나 느리면 '음성 안내 속도'를 조절해 보세요.
                 주변 탐색 범위가 너무 넓거나 좁으면 '기본 탐색 반경'을 변경할 수 있습니다.
                 위급 상황에 연락받을 보호자 전화번호는 'SOS 설정'에서 미리 등록해 두세요.
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
