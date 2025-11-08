import Foundation
import Vapor

public class LookupClient {
    private let baseURL: String?
    private let cache: InMemoryCache<String>
    private let client: Client
    private let logger: Logger
    
    public struct AirlineLookup: Codable {
        let displayNameFull: String?
        
        enum CodingKeys: String, CodingKey {
            case displayNameFull = "display_name_full"
        }
    }
    
    public struct AircraftLookup: Codable {
        let displayNameShort: String?
        let displayNameFull: String?
        
        enum CodingKeys: String, CodingKey {
            case displayNameShort = "display_name_short"
            case displayNameFull = "display_name_full"
        }
    }
    
    public init(
        baseURL: String?,
        client: Client,
        logger: Logger
    ) {
        self.baseURL = baseURL
        self.cache = InMemoryCache<String>()
        self.client = client
        self.logger = logger
    }
    
    public func lookupAirline(icao: String) async throws -> String? {
        guard let baseURL = baseURL else { return nil }
        
        // Check cache
        let cacheKey = "airline:\(icao)"
        if let cached = cache.get(cacheKey) {
            return cached
        }
        
        let url = "\(baseURL)/oss/lookup/airline/\(icao).json"
        
        do {
            let request = ClientRequest(method: .GET, url: URI(string: url))
            let response = try await client.send(request)
            
            guard response.status == .ok else {
                logger.debug("Airline lookup failed for \(icao): \(response.status)")
                return nil
            }
            
            let lookup = try response.content.decode(AirlineLookup.self)
            let displayName = lookup.displayNameFull
            
            if let displayName = displayName {
                cache.set(cacheKey, value: displayName, ttlSeconds: 3600)
            }
            
            return displayName
        } catch {
            logger.debug("Airline lookup error for \(icao): \(error)")
            return nil
        }
    }
    
    public func lookupAircraft(icao: String) async throws -> String? {
        guard let baseURL = baseURL else { return nil }
        
        // Check cache
        let cacheKey = "aircraft:\(icao)"
        if let cached = cache.get(cacheKey) {
            return cached
        }
        
        let url = "\(baseURL)/oss/lookup/aircraft/\(icao).json"
        
        do {
            let request = ClientRequest(method: .GET, url: URI(string: url))
            let response = try await client.send(request)
            
            guard response.status == .ok else {
                logger.debug("Aircraft lookup failed for \(icao): \(response.status)")
                return nil
            }
            
            let lookup = try response.content.decode(AircraftLookup.self)
            let displayName = lookup.displayNameShort ?? lookup.displayNameFull
            
            if let displayName = displayName {
                cache.set(cacheKey, value: displayName, ttlSeconds: 3600)
            }
            
            return displayName
        } catch {
            logger.debug("Aircraft lookup error for \(icao): \(error)")
            return nil
        }
    }
}

