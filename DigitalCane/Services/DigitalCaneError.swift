import Foundation

enum DigitalCaneError: Error, LocalizedError {
    case networkError(String)
    case parsingError(String)
    case locationError(String)
    case invalidResponse
    case missingAPIKey
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "네트워크 오류가 발생했습니다: \(message)"
        case .parsingError(let message):
            return "데이터 처리 중 오류가 발생했습니다: \(message)"
        case .locationError(let message):
            return "위치 서비스 오류: \(message)"
        case .invalidResponse:
            return "서버로부터 유효하지 않은 응답을 받았습니다."
        case .missingAPIKey:
            return "API 키가 설정되지 않았습니다."
        case .unknown(let message):
            return "알 수 없는 오류가 발생했습니다: \(message)"
        }
    }
}
