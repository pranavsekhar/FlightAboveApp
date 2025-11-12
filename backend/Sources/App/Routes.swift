import Foundation
import Vapor

// Extension for chunking arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// Helper function to convert ICAO to IATA (simple fallback)
private func convertIcaoToIata(_ icao: String) -> String? {
    // US airports: KXXX -> XXX (remove leading K)
    if icao.count == 4 && icao.hasPrefix("K") {
        return String(icao.dropFirst())
    }
    // Canadian airports: CXXX -> XXX (remove leading C)
    if icao.count == 4 && icao.hasPrefix("C") {
        return String(icao.dropFirst())
    }
    // Some other patterns - this is a basic fallback
    // For a complete solution, you'd need a lookup table
    return nil
}

// Configuration constants
private let DEFAULT_RADIUS_KM = 60.0
private let MIN_RADIUS_KM = 10.0
private let MAX_RADIUS_KM = 120.0
private let ELEV_THRESHOLD_DEG = 0.0  // Minimum elevation angle in degrees (0° = any visible aircraft, was 5°)
private let RESULTS_LIMIT = 6
private let MAX_ENRICH_CONCURRENCY = 3

func routes(_ app: Application) throws {
    // Get environment variables
    guard let openSkyId = Environment.get("OPENSKY_ID"),
          let openSkySecret = Environment.get("OPENSKY_SECRET"),
          let aeroAPIKey = Environment.get("AEROAPI_KEY") else {
        fatalError("Missing required environment variables: OPENSKY_ID, OPENSKY_SECRET, AEROAPI_KEY")
    }
    
    let lookupCDNBase = Environment.get("LOOKUP_CDN_BASE")
    
    // Initialize clients
    let openSkyClient = OpenSkyClient(
        clientId: openSkyId,
        clientSecret: openSkySecret,
        client: app.client,
        logger: app.logger
    )
    
    let aeroAPIClient = AeroAPIClient(
        apiKey: aeroAPIKey,
        client: app.client,
        logger: app.logger
    )
    
    let lookupClient = LookupClient(
        baseURL: lookupCDNBase,
        client: app.client,
        logger: app.logger
    )
    
    // Diagnostic endpoint to test connectivity
    app.get("health", "opensky") { req async throws -> [String: String] in
        let testURL = "https://opensky-network.org/api/states/all?lamin=37&lamax=38&lomin=-123&lomax=-122"
        let startTime = Date()
        
        do {
            var testRequest = ClientRequest(method: .GET, url: URI(string: testURL))
            testRequest.headers.add(name: "User-Agent", value: "FlightAbove/1.0")
            let response = try await app.client.send(testRequest)
            let duration = Date().timeIntervalSince(startTime)
            
            return [
                "status": "success",
                "opensky_api_reachable": "true",
                "response_time_seconds": String(format: "%.2f", duration),
                "http_status": "\(response.status.code)"
            ]
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return [
                "status": "error",
                "opensky_api_reachable": "false",
                "response_time_seconds": String(format: "%.2f", duration),
                "error": "\(error)"
            ]
        }
    }
    
    app.get("above") { req async throws -> AboveResponse in
        // Parse query parameters
        guard let lat = try? req.query.get(Double.self, at: "lat"),
              let lon = try? req.query.get(Double.self, at: "lon") else {
            throw Abort(.badRequest, reason: "Missing required parameters: lat, lon")
        }
        
        var radiusKm: Double
        if let radius = try? req.query.get(Double.self, at: "radius_km") {
            radiusKm = radius
        } else {
            radiusKm = DEFAULT_RADIUS_KM
        }
        radiusKm = max(MIN_RADIUS_KM, min(MAX_RADIUS_KM, radiusKm))
        
        // Round coordinates for logging (privacy)
        let roundedLat = round(lat * 1000) / 1000
        let roundedLon = round(lon * 1000) / 1000
        req.logger.info("Request: lat=\(roundedLat), lon=\(roundedLon), radius=\(radiusKm)km")
        
        var errors: [String] = []
        let updatedAt = ISO8601DateFormatter().string(from: Date())
        
        // Compute bounding box
        let bbox = Geo.centeredBoundingBox(lat: lat, lon: lon, radiusKm: radiusKm)
        
        // Fetch state vectors from OpenSky
        let stateVectors: [StateVector]
        do {
            stateVectors = try await openSkyClient.fetchStates(
                latMin: bbox.latMin,
                latMax: bbox.latMax,
                lonMin: bbox.lonMin,
                lonMax: bbox.lonMax
            )
            req.logger.info("Fetched \(stateVectors.count) state vectors from OpenSky (bbox: lat[\(bbox.latMin), \(bbox.latMax)], lon[\(bbox.lonMin), \(bbox.lonMax)])")
            
            // Log sample of what we got
            if !stateVectors.isEmpty {
                let sample = stateVectors.prefix(5).map { sv in
                    let hasPos = (sv.lat != nil && sv.lon != nil) ? "✓" : "✗"
                    let alt = sv.geoAltitude.map { String(format: "%.0fm", $0) } ?? "N/A"
                    return "\(sv.callsign ?? "N/A"): pos\(hasPos) alt\(alt)"
                }.joined(separator: ", ")
                req.logger.info("Sample state vectors: \(sample)")
            }
        } catch {
            req.logger.error("OpenSky fetch failed: \(error)")
            errors.append("opensky_fetch_failed")
            return AboveResponse(
                updatedAt: updatedAt,
                center: AboveResponse.Center(lat: lat, lon: lon),
                aircraft: [],
                errors: errors
            )
        }
        
        // Process state vectors: compute distances, bearings, elevation
        struct ProcessedAircraft {
            let stateVector: StateVector
            let distanceKm: Double
            let bearingDeg: Double
            let elevDeg: Double
        }
        
        var processed: [ProcessedAircraft] = []
        var skippedNoPosition = 0
        var skippedRadius = 0
        var skippedElevation = 0
        
        for sv in stateVectors {
            guard let svLat = sv.lat,
                  let svLon = sv.lon,
                  let geoAlt = sv.geoAltitude else {
                skippedNoPosition += 1
                continue
            }
            
            // Filter by radius
            let distanceKm = Geo.haversineKm(lat1: lat, lon1: lon, lat2: svLat, lon2: svLon)
            if distanceKm > radiusKm {
                skippedRadius += 1
                continue
            }
            
            // Compute bearing and elevation
            let bearingDeg = Geo.computeBearingDeg(lat1: lat, lon1: lon, lat2: svLat, lon2: svLon)
            let elevDeg = Geo.computeElevationDeg(
                aircraftAltM: geoAlt,
                userAltM: 0.0,
                groundDistanceKm: distanceKm
            )
            
            // Filter by elevation threshold
            if elevDeg >= ELEV_THRESHOLD_DEG {
                processed.append(ProcessedAircraft(
                    stateVector: sv,
                    distanceKm: distanceKm,
                    bearingDeg: bearingDeg,
                    elevDeg: elevDeg
                ))
            } else {
                skippedElevation += 1
            }
        }
        
        req.logger.info("Filtered aircraft: \(processed.count) passed, \(skippedNoPosition) no position, \(skippedRadius) outside radius, \(skippedElevation) below elevation threshold")
        
        // Log sample elevations for debugging
        if !processed.isEmpty {
            let sampleElevations = processed.prefix(10).map { String(format: "%.1f°", $0.elevDeg) }.joined(separator: ", ")
            req.logger.info("Sample elevation angles (first 10): \(sampleElevations)")
        }
        
        // Sort by elevation descending and take top N
        processed.sort { $0.elevDeg > $1.elevDeg }
        let topAircraft = Array(processed.prefix(RESULTS_LIMIT))
        
        req.logger.info("Selected top \(topAircraft.count) aircraft for enrichment (elevations: \(topAircraft.map { String(format: "%.1f°", $0.elevDeg) }.joined(separator: ", ")))")
        
        // Enrich with AeroAPI (with concurrency limit)
        var enrichedAircraft: [AboveResponse.Aircraft] = []
        
        // Process in batches to limit concurrency
        let batches = topAircraft.chunked(into: MAX_ENRICH_CONCURRENCY)
        
        for batch in batches {
            let results = await withTaskGroup(of: AboveResponse.Aircraft?.self) { group -> [AboveResponse.Aircraft] in
                for processed in batch {
                    let callsign = processed.stateVector.callsign?.trimmingCharacters(in: .whitespaces) ?? ""
                    
                    group.addTask {
                        var flightInfo: FlightInfo? = nil
                        if !callsign.isEmpty {
                            do {
                                flightInfo = try await aeroAPIClient.fetchFlightInfo(callsign: callsign)
                                if flightInfo == nil {
                                    req.logger.debug("AeroAPI returned no flight info for callsign: \(callsign)")
                                }
                            } catch {
                                req.logger.warning("AeroAPI enrichment failed for \(callsign): \(error)")
                            }
                        } else {
                            req.logger.debug("Skipping AeroAPI lookup - no callsign for ICAO24: \(processed.stateVector.icao24)")
                        }
                        
                        // Get IATA codes from AeroAPI first
                        var originIata = flightInfo?.origin?.codeIata
                        var destIata = flightInfo?.destination?.codeIata
                        
                        // Lookup airline, aircraft, and airport names
                        var airlineName: String? = nil
                        var aircraftNameShort: String? = nil
                        var aircraftNameFull: String? = nil
                        var originName: String? = nil
                        var destinationName: String? = nil
                        
                        // Log what we have from AeroAPI for debugging
                        if let flightInfo = flightInfo {
                            req.logger.debug("AeroAPI flight info: origin=\(flightInfo.origin?.codeIata ?? flightInfo.origin?.codeIcao ?? "nil"), dest=\(flightInfo.destination?.codeIata ?? flightInfo.destination?.codeIcao ?? "nil"), operator=\(flightInfo.operatorIcao ?? "nil")")
                        }
                        
                        if let operatorIcao = flightInfo?.operatorIcao, !operatorIcao.isEmpty {
                            do {
                                airlineName = try await lookupClient.lookupAirline(icao: operatorIcao)
                                req.logger.debug("Airline lookup for \(operatorIcao): \(airlineName ?? "nil")")
                            } catch {
                                req.logger.warning("Airline lookup failed for \(operatorIcao): \(error)")
                            }
                        } else {
                            req.logger.debug("No operator ICAO available for airline lookup")
                        }
                        
                        if let aircraftType = flightInfo?.aircraftType, !aircraftType.isEmpty {
                            do {
                                // Get both short and full aircraft names
                                let aircraftLookup = try await lookupClient.lookupAircraft(icao: aircraftType)
                                aircraftNameShort = aircraftLookup.short
                                aircraftNameFull = aircraftLookup.full
                            } catch {
                                // Ignore lookup errors
                            }
                        }
                        
                        // Lookup airport names and IATA codes
                        if let originIcao = flightInfo?.origin?.codeIcao, !originIcao.isEmpty {
                            do {
                                let airportLookup = try await lookupClient.lookupAirport(icao: originIcao)
                                originName = airportLookup.name
                                // Use IATA from lookup if AeroAPI didn't provide it
                                if originIata == nil {
                                    originIata = airportLookup.iata
                                }
                            } catch {
                                req.logger.debug("Airport lookup failed for origin \(originIcao): \(error)")
                            }
                        }
                        
                        if let destIcao = flightInfo?.destination?.codeIcao, !destIcao.isEmpty {
                            do {
                                let airportLookup = try await lookupClient.lookupAirport(icao: destIcao)
                                destinationName = airportLookup.name
                                // Use IATA from lookup if AeroAPI didn't provide it
                                if destIata == nil {
                                    destIata = airportLookup.iata
                                }
                            } catch {
                                req.logger.debug("Airport lookup failed for destination \(destIcao): \(error)")
                            }
                        }
                        
                        // Final fallback: convert ICAO to IATA if still not available
                        if originIata == nil, let originIcao = flightInfo?.origin?.codeIcao {
                            originIata = convertIcaoToIata(originIcao)
                        }
                        if destIata == nil, let destIcao = flightInfo?.destination?.codeIcao {
                            destIata = convertIcaoToIata(destIcao)
                        }
                        
                        // Build aircraft response (always return aircraft, even without enrichment)
                        let sv = processed.stateVector
                        let altFt = sv.geoAltitude.map { Geo.metersToFeet($0) }
                        let gsKt = sv.velocity.map { Geo.msToKnots($0) }
                        let distNm = Geo.kmToNauticalMiles(processed.distanceKm)
                        
                        // Always return aircraft - enrichment is optional
                        return AboveResponse.Aircraft(
                            icao24: sv.icao24,
                            callsign: sv.callsign?.trimmingCharacters(in: .whitespaces),
                            altFt: altFt,
                            gsKt: gsKt,
                            bearingDeg: processed.bearingDeg,
                            distNm: distNm,
                            elevDeg: processed.elevDeg,
                            airline: airlineName,
                            originIcao: flightInfo?.origin?.codeIcao,
                            originIata: originIata,
                            originName: originName,
                            destinationIcao: flightInfo?.destination?.codeIcao,
                            destinationIata: destIata,
                            destinationName: destinationName,
                            aircraftType: flightInfo?.aircraftType,
                            aircraftNameShort: aircraftNameShort,
                            aircraftNameFull: aircraftNameFull
                        )
                    }
                }
                
                var results: [AboveResponse.Aircraft] = []
                var nilCount = 0
                for await result in group {
                    if let aircraft = result {
                        results.append(aircraft)
                    } else {
                        nilCount += 1
                        req.logger.warning("Received nil aircraft from enrichment task")
                    }
                }
                if nilCount > 0 {
                    req.logger.warning("\(nilCount) aircraft failed to enrich (returned nil)")
                }
                return results
            }
            
            enrichedAircraft.append(contentsOf: results)
        }
        
        // Sort enriched aircraft by elevation (maintain order)
        enrichedAircraft.sort { a1, a2 in
            (a1.elevDeg ?? 0) > (a2.elevDeg ?? 0)
        }
        
        return AboveResponse(
            updatedAt: updatedAt,
            center: AboveResponse.Center(lat: lat, lon: lon),
            aircraft: enrichedAircraft,
            errors: errors.isEmpty ? nil : errors
        )
    }
}

