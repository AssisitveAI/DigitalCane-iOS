import Foundation
import CoreLocation

/// 날씨 정보를 제공하는 서비스 클래스 (Open-Meteo API 사용)
class WeatherService {
    static let shared = WeatherService()
    
    private init() {}
    
    /// 현재 위치의 날씨 정보를 가져와 음성 안내용 문자열로 반환합니다.
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> String {
        // 네트워크 연결 확인
        if !NetworkMonitor.shared.isConnected {
            throw DigitalCaneError.notConnected
        }
        
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true&timezone=auto"
        guard let url = URL(string: urlString) else {
            throw DigitalCaneError.unknown("Invalid Weather URL")
        }
        
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DigitalCaneError.networkError("Weather API Error")
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let temp = decodedResponse.current_weather.temperature
            let weatherCode = decodedResponse.current_weather.weathercode
            
            let condition = self.interpretWeatherCode(weatherCode)
            let safetyGuidance = self.getSafetyGuidance(for: weatherCode)
            
            var message = "현재 기온은 \(Int(temp))도이며, \(condition)입니다."
            if !safetyGuidance.isEmpty {
                message += " \(safetyGuidance)"
            }
            
            return message
        } catch {
            throw DigitalCaneError.parsingError("Weather Data Parsing Failed")
        }
    }
    
    /// Weather Code를 한국어 설명으로 변환
    private func interpretWeatherCode(_ code: Int) -> String {
        switch code {
        case 0: return "맑은 하늘"
        case 1, 2, 3: return "대체로 맑음"
        case 45, 48: return "안개"
        case 51, 53, 55: return "이슬비"
        case 61, 63, 65: return "비"
        case 71, 73, 75: return "눈"
        case 77: return "싸락눈"
        case 80, 81, 82: return "소나기"
        case 85, 86: return "소나기성 눈"
        case 95, 96, 99: return "천둥번개"
        default: return "흐림"
        }
    }
    
    /// 시각장애인 사용자를 위한 날씨별 안전 가이드 제공
    private func getSafetyGuidance(for code: Int) -> String {
        switch code {
        case 45, 48:
            return "안개로 인해 주변 장애물 인지가 어려울 수 있으니 주의하세요."
        case 51, 53, 55, 61, 63, 65, 80, 81, 82:
            return "바닥이 미끄러우니 보행 시 주의하시고 지팡이 끝의 진동에 집중해 주세요."
        case 71, 73, 75, 77, 85, 86:
            return "쌓인 눈으로 인해 지면의 질감 파악이 어려울 수 있습니다. 천천히 이동하세요."
        case 95, 96, 99:
            return "낙뢰 위험이 있으니 가급적 실내에 머무르시는 것을 권장합니다."
        default:
            return ""
        }
    }
}

// MARK: - Data Models (Open-Meteo)
struct OpenMeteoResponse: Codable {
    let current_weather: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature: Double
    let weathercode: Int
    let windspeed: Double
}
