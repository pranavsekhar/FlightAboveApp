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
    
    public struct AirportLookup: Codable {
        let displayNameFull: String?
        let codeIata: String?
        
        enum CodingKeys: String, CodingKey {
            case displayNameFull = "display_name_full"
            case codeIata = "code_iata"
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
    
    public func lookupAircraft(icao: String) async throws -> (short: String?, full: String?) {
        guard let baseURL = baseURL else { return (nil, nil) }
        
        // Check cache - we'll cache the full response
        let cacheKey = "aircraft:\(icao)"
        if let cached = cache.get(cacheKey) {
            // Return cached short name, full name if available
            return (cached, cached) // For now, return same for both
        }
        
        let url = "\(baseURL)/oss/lookup/aircraft/\(icao).json"
        
        do {
            let request = ClientRequest(method: .GET, url: URI(string: url))
            let response = try await client.send(request)
            
            guard response.status == .ok else {
                logger.debug("Aircraft lookup failed for \(icao): \(response.status)")
                return (nil, nil)
            }
            
            let lookup = try response.content.decode(AircraftLookup.self)
            let shortName = lookup.displayNameShort
            let fullName = lookup.displayNameFull ?? lookup.displayNameShort
            
            // Cache the short name (for backward compatibility)
            if let shortName = shortName {
                cache.set(cacheKey, value: shortName, ttlSeconds: 3600)
            }
            
            return (shortName, fullName)
        } catch {
            logger.debug("Aircraft lookup error for \(icao): \(error)")
            return (nil, nil)
        }
    }
    
    public func lookupAirport(icao: String) async throws -> (name: String?, iata: String?) {
        guard let baseURL = baseURL else { return (nil, nil) }
        
        // Check cache - we'll cache the name
        let cacheKey = "airport:\(icao)"
        if let cached = cache.get(cacheKey) {
            return (cached, nil) // IATA not cached separately
        }
        
        let url = "\(baseURL)/oss/lookup/airport/\(icao).json"
        
        do {
            let request = ClientRequest(method: .GET, url: URI(string: url))
            let response = try await client.send(request)
            
            guard response.status == .ok else {
                logger.debug("Airport lookup failed for \(icao): \(response.status)")
                return (nil, nil)
            }
            
            let lookup = try response.content.decode(AirportLookup.self)
            let displayName = lookup.displayNameFull
            let iataCode = lookup.codeIata
            
            if let displayName = displayName {
                cache.set(cacheKey, value: displayName, ttlSeconds: 3600)
            }
            
            return (displayName, iataCode)
        } catch {
            logger.debug("Airport lookup error for \(icao): \(error)")
            return (nil, nil)
        }
    }
}

