import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // 배경: 은은한 깊이감 있는 그라데이션
            LinearGradient(gradient: Gradient(colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.15)]),
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // 로고 애니메이션
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .opacity(isAnimating ? 0.0 : 1.0)
                        .animation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
                    
                    Image(systemName: "figure.walk.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 10, x: 0, y: 0)
                        .scaleEffect(isAnimating ? 1.05 : 1.0)
                        .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                }
                
                VStack(spacing: 15) {
                    Text("Digital Cane")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                    
                    Text("당신의 눈이 되어드릴게요")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // 제작자 표기: 깔끔한 푸터 스타일
                VStack(spacing: 8) {
                    Text("Designed & Developed by")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(1.5)
                    
                    Text("KAIST Assistive AI Lab")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
