import Foundation
import Vapor

public class OpenSkyClient {
    private let clientId: String
    private let clientSecret: String
    private let baseURL: String
    private let tokenURL: String
    private let cache: InMemoryCache<OpenSkyToken>
    private let client: Client
    private let logger: Logger
    
    private struct OpenSkyToken: Codable {
        let accessToken: String
        let expiresAt: Date
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt
        }
    }
    
    private struct TokenResponse: Codable {
        let accessToken: String
        let expiresIn: Int
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }
    
    public init(
        clientId: String,
        clientSecret: String,
        baseURL: String = "https://opensky-network.org",
        tokenURL: String = "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token",
        client: Client,
        logger: Logger
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.baseURL = baseURL
        self.tokenURL = tokenURL
        self.cache = InMemoryCache<OpenSkyToken>()
        self.client = client
        self.logger = logger
    }
    
    private func getAccessToken() async throws -> String {
        // Check cache first
        if let cached = cache.get("token") {
            let skewSeconds: TimeInterval = 60
            if cached.expiresAt > Date().addingTimeInterval(skewSeconds) {
                logger.info("Using cached OpenSky token")
                return cached.accessToken
            }
        }
        
        // Request new token
        logger.info("Fetching new OpenSky token")
        var tokenRequest = ClientRequest(method: .POST, url: URI(string: tokenURL))
        tokenRequest.headers.contentType = .urlEncodedForm
        let bodyString = "grant_type=client_credentials&client_id=\(clientId)&client_secret=\(clientSecret)"
        tokenRequest.body = .init(string: bodyString)
        
        let body: ClientResponse
        do {
            body = try await client.send(tokenRequest)
        } catch {
            logger.error("OpenSky token request network error: \(error)")
            throw Abort(.internalServerError, reason: "Network error while obtaining OpenSky token: \(error.localizedDescription)")
        }
        
        guard body.status == .ok else {
            // Try to read error response body
            var errorMessage = "Status: \(body.status)"
            if let bodyBuffer = body.body {
                do {
                    if let bodyData = bodyBuffer.getData(at: 0, length: bodyBuffer.readableBytes) {
                        if let errorString = String(data: bodyData, encoding: .utf8) {
                            errorMessage += ", Response: \(errorString)"
                        }
                    }
                } catch {
                    // Ignore body read errors
                }
            }
            logger.error("OpenSky token request failed: \(errorMessage)")
            throw Abort(.internalServerError, reason: "Failed to obtain OpenSky token: \(errorMessage)")
        }
        
        let tokenResponse = try body.content.decode(TokenResponse.self)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        
        let token = OpenSkyToken(accessToken: tokenResponse.accessToken, expiresAt: expiresAt)
        cache.set("token", value: token, ttlSeconds: TimeInterval(tokenResponse.expiresIn))
        
        return tokenResponse.accessToken
    }
    
    public func fetchStates(
        latMin: Double,
        latMax: Double,
        lonMin: Double,
        lonMax: Double
    ) async throws -> [StateVector] {
        let token = try await getAccessToken()
        
        let url = "\(baseURL)/api/states/all?lamin=\(latMin)&lamax=\(latMax)&lomin=\(lonMin)&lomax=\(lonMax)"
        logger.info("Fetching OpenSky states from: \(url)")
        
        var request = ClientRequest(method: .GET, url: URI(string: url))
        request.headers.bearerAuthorization = BearerAuthorization(token: token)
        request.headers.add(name: "User-Agent", value: "FlightAbove/1.0")
        
        let response: ClientResponse
        do {
            response = try await client.send(request)
        } catch {
            logger.error("OpenSky states request network error: \(error)")
            throw Abort(.internalServerError, reason: "Network error while fetching OpenSky states: \(error.localizedDescription)")
        }
        
        guard response.status == .ok else {
            // Try to read error response body
            var errorMessage = "Status: \(response.status)"
            if let bodyBuffer = response.body {
                do {
                    if let bodyData = bodyBuffer.getData(at: 0, length: bodyBuffer.readableBytes) {
                        if let errorString = String(data: bodyData, encoding: .utf8) {
                            errorMessage += ", Response: \(errorString.prefix(500))" // Limit to 500 chars
                        }
                    }
                } catch {
                    // Ignore body read errors
                }
            }
            
            if response.status == .unauthorized {
                // Try refreshing token once
                logger.warning("OpenSky request unauthorized, refreshing token")
                cache.remove("token")
                let newToken = try await getAccessToken()
                var retryRequest = ClientRequest(method: .GET, url: URI(string: url))
                retryRequest.headers.bearerAuthorization = BearerAuthorization(token: newToken)
                retryRequest.headers.add(name: "User-Agent", value: "FlightAbove/1.0")
                
                let retryResponse: ClientResponse
                do {
                    retryResponse = try await client.send(retryRequest)
                } catch {
                    logger.error("OpenSky retry request network error: \(error)")
                    throw Abort(.internalServerError, reason: "Network error on retry: \(error.localizedDescription)")
                }
                
                guard retryResponse.status == .ok else {
                    var retryErrorMessage = "Status: \(retryResponse.status)"
                    if let bodyBuffer = retryResponse.body {
                        do {
                            if let bodyData = bodyBuffer.getData(at: 0, length: bodyBuffer.readableBytes) {
                                if let errorString = String(data: bodyData, encoding: .utf8) {
                                    retryErrorMessage += ", Response: \(errorString.prefix(500))"
                                }
                            }
                        } catch {
                            // Ignore body read errors
                        }
                    }
                    logger.error("OpenSky request failed after token refresh: \(retryErrorMessage)")
                    throw Abort(.internalServerError, reason: "OpenSky API request failed after token refresh: \(retryErrorMessage)")
                }
                return try parseStatesResponse(retryResponse)
            }
            logger.error("OpenSky request failed: \(errorMessage)")
            throw Abort(.internalServerError, reason: "OpenSky API request failed: \(errorMessage)")
        }
        
        return try parseStatesResponse(response)
    }
    
    private func parseStatesResponse(_ response: ClientResponse) throws -> [StateVector] {
        struct OpenSkyResponse: Codable {
            let states: [[AnyCodable]]?
        }
        
        // Parse JSON manually to handle array format
        guard let bodyBuffer = response.body else {
            logger.warning("OpenSky response has no body")
            return []
        }
        
        guard let body = bodyBuffer.getData(at: 0, length: bodyBuffer.readableBytes) else {
            logger.warning("OpenSky response body could not be read")
            return []
        }
        
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            logger.warning("OpenSky response is not a JSON object")
            return []
        }
        
        guard let statesArray = json["states"] as? [[Any]] else {
            logger.info("OpenSky response has no states array (or states is null)")
            return []
        }
        
        logger.info("OpenSky returned \(statesArray.count) state vectors")
        
        var stateVectors: [StateVector] = []
        for stateArray in statesArray {
            if let sv = StateVector(from: stateArray) {
                stateVectors.append(sv)
            }
        }
        
        logger.info("Parsed \(stateVectors.count) valid state vectors")
        return stateVectors
    }
}

// Helper to decode Any values
private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
