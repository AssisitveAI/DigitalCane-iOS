// 임시 코드 - ContentView 수정 참고용

// NavigationModeView에 추가할 헬퍼 함수
private func buildRouteText() -> String {
    var text = ""
    
    for (index, step) in navigationManager.steps.enumerated() {
        text += "단계 \(index + 1): \(step.action)\n"
        text += "\(step.instruction)\n"
        
        if !step.detail.isEmpty {
            text += "\(step.detail)\n"
        }
        
        text += "\n" // 단계 구분
    }
    
    return text
}

// ScrollView 부분을 이렇게 교체:
ScrollView {
    if navigationManager.steps.isEmpty {
        Text("경로 정보를 불러오는 중입니다...")
            .foregroundColor(.gray)
            .padding()
    } else {
        Text(buildRouteText())
            .font(.body)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
.background(Color.black)
