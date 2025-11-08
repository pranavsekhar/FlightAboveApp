import Foundation
import Vapor

public class AeroAPIClient {
    private let apiKey: String
    private let baseURL: String
    private let cache: InMemoryCache<FlightInfo>
    private let client: Client
    private let logger: Logger
    
    public init(
        apiKey: String,
        baseURL: String = "https://aeroapi.flightaware.com/aeroapi",
        client: Client,
        logger: Logger
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.cache = InMemoryCache<FlightInfo>()
        self.client = client
        self.logger = logger
    }
    
    public func fetchFlightInfo(callsign: String) async throws -> FlightInfo? {
        // Check cache first
        if let cached = cache.get(callsign) {
            logger.debug("Using cached AeroAPI data for \(callsign)")
            return cached
        }
        
        let url = "\(baseURL)/flights/\(callsign)"
        
        do {
            var request = ClientRequest(method: .GET, url: URI(string: url))
            request.headers.add(name: "x-apikey", value: apiKey)
            request.headers.add(name: "Accept", value: "application/json")
            let response = try await client.send(request)
            
            guard response.status == .ok else {
                if response.status == .notFound {
                    logger.debug("Flight not found in AeroAPI: \(callsign)")
                    return nil
                }
                logger.warning("AeroAPI request failed for \(callsign): \(response.status)")
                return nil
            }
            
            let aeroResponse = try response.content.decode(AeroAPIResponse.self)
            
            guard let flight = aeroResponse.flights?.first else {
                logger.debug("No flights in AeroAPI response for \(callsign)")
                return nil
            }
            
            // Cache for 2-5 minutes (using 180 seconds as specified)
            cache.set(callsign, value: flight, ttlSeconds: 180)
            
            return flight
        } catch {
            logger.error("AeroAPI request error for \(callsign): \(error)")
            return nil
        }
    }
}

