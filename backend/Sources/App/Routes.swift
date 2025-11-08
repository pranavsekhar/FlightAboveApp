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

// Configuration constants
private let DEFAULT_RADIUS_KM = 60.0
private let MIN_RADIUS_KM = 10.0
private let MAX_RADIUS_KM = 120.0
private let ELEV_THRESHOLD_DEG = 70.0
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
    let port = Environment.get("PORT").flatMap { Int($0) } ?? 8080
    
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
    
    app.get("above") { req async throws -> AboveResponse in
        // Parse query parameters
        guard let lat = try? req.query.get(Double.self, at: "lat"),
              let lon = try? req.query.get(Double.self, at: "lon") else {
            throw Abort(.badRequest, reason: "Missing required parameters: lat, lon")
        }
        
        var radiusKm = try req.query.get(Double.self, at: "radius_km") ?? DEFAULT_RADIUS_KM
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
        
        for sv in stateVectors {
            guard let svLat = sv.lat,
                  let svLon = sv.lon,
                  let geoAlt = sv.geoAltitude else {
                continue
            }
            
            // Filter by radius
            let distanceKm = Geo.haversineKm(lat1: lat, lon1: lon, lat2: svLat, lon2: svLon)
            if distanceKm > radiusKm {
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
            }
        }
        
        // Sort by elevation descending and take top N
        processed.sort { $0.elevDeg > $1.elevDeg }
        let topAircraft = Array(processed.prefix(RESULTS_LIMIT))
        
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
                            } catch {
                                req.logger.warning("AeroAPI enrichment failed for \(callsign): \(error)")
                            }
                        }
                        
                        // Optionally lookup airline and aircraft names
                        var airlineName: String? = nil
                        var aircraftNameShort: String? = nil
                        
                        if let operatorIcao = flightInfo?.operatorIcao, !operatorIcao.isEmpty {
                            do {
                                airlineName = try await lookupClient.lookupAirline(icao: operatorIcao)
                            } catch {
                                // Ignore lookup errors
                            }
                        }
                        
                        if let aircraftType = flightInfo?.aircraftType, !aircraftType.isEmpty {
                            do {
                                aircraftNameShort = try await lookupClient.lookupAircraft(icao: aircraftType)
                            } catch {
                                // Ignore lookup errors
                            }
                        }
                        
                        // Build aircraft response
                        let sv = processed.stateVector
                        let altFt = sv.geoAltitude.map { Geo.metersToFeet($0) }
                        let gsKt = sv.velocity.map { Geo.msToKnots($0) }
                        let distNm = Geo.kmToNauticalMiles(processed.distanceKm)
                        
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
                            destinationIcao: flightInfo?.destination?.codeIcao,
                            aircraftType: flightInfo?.aircraftType,
                            aircraftNameShort: aircraftNameShort
                        )
                    }
                }
                
                var results: [AboveResponse.Aircraft] = []
                for await result in group {
                    if let aircraft = result {
                        results.append(aircraft)
                    }
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

