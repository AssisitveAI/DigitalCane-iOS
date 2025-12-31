import Foundation

class WeatherService {
    static let shared = WeatherService()
    
    private init() {}
    
    /// OpenMeteo API (Free, No Key)를 사용하여 현재 날씨를 가져옵니다.
    /// - Parameters:
    ///   - latitude: 위도
    ///   - longitude: 경도
    ///   - completion: (날씨 설명 문자열?, 에러?) -> Void
    func fetchCurrentWeather(latitude: Double, longitude: Double, completion: @escaping (String?, Error?) -> Void) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true&timezone=auto"
        guard let url = URL(string: urlString) else {
            completion(nil, NSError(domain: "WeatherService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Weather Fetch Error: \(error)")
                completion(nil, error)
                return
            }
            
            guard let data = data else {
                completion(nil, NSError(domain: "WeatherService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let temp = decodedResponse.current_weather.temperature
                let weatherCode = decodedResponse.current_weather.weathercode
                
                let condition = self.interpretWeatherCode(weatherCode)
                let message = "현재 기온은 \(temp)도이며, \(condition)입니다."
                
                print("🌤️ Weather: \(message)")
                completion(message, nil)
            } catch {
                print("Weather Configuration Error: \(error)")
                completion(nil, error)
            }
        }.resume()
    }
    
    private func interpretWeatherCode(_ code: Int) -> String {
        // WMO Weather interpretation codes (WW)
        switch code {
        case 0: return "맑음"
        case 1, 2, 3: return "구름이 조금 있음"
        case 45, 48: return "안개가 낌"
        case 51, 53, 55: return "이슬비가 내림"
        case 61, 63, 65: return "비가 내림"
        case 71, 73, 75: return "눈이 내림"
        case 80, 81, 82: return "소나기가 내림"
        case 95, 96, 99: return "천둥번개가 침"
        default: return "흐림"
        }
    }
}

// MARK: - Data Models
struct OpenMeteoResponse: Codable {
    let current_weather: CurrentWeather
}

struct CurrentWeather: Codable {
    let temperature: Double
    let weathercode: Int
    let windspeed: Double
}
