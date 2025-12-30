import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "figure.walk")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.yellow)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                
                Text("Digital Cane")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                
                Text("당신의 눈이 되어드릴게요")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
