import Foundation
import Vapor

public struct AboveResponse: Content {
    public let updatedAt: String
    public let center: Center
    public let aircraft: [Aircraft]
    public let errors: [String]?
    
    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case center
        case aircraft
        case errors
    }
    
    public struct Center: Codable, Sendable {
        public let lat: Double
        public let lon: Double
    }
    
    public struct Aircraft: Codable, Identifiable, Sendable {
        public var id: String {
            icao24 + (callsign ?? "")
        }
        
        public let icao24: String
        public let callsign: String?
        public let altFt: Double?
        public let gsKt: Double?
        public let bearingDeg: Double?
        public let distNm: Double?
        public let elevDeg: Double?
        public let airline: String?
        public let originIcao: String?
        public let originIata: String?
        public let originName: String?
        public let destinationIcao: String?
        public let destinationIata: String?
        public let destinationName: String?
        public let aircraftType: String?
        public let aircraftNameShort: String?
        public let aircraftNameFull: String?
        
        enum CodingKeys: String, CodingKey {
            case icao24
            case callsign
            case altFt = "alt_ft"
            case gsKt = "gs_kt"
            case bearingDeg = "bearing_deg"
            case distNm = "dist_nm"
            case elevDeg = "elev_deg"
            case airline
            case originIcao = "origin_icao"
            case originIata = "origin_iata"
            case originName = "origin_name"
            case destinationIcao = "destination_icao"
            case destinationIata = "destination_iata"
            case destinationName = "destination_name"
            case aircraftType = "aircraft_type"
            case aircraftNameShort = "aircraft_name_short"
            case aircraftNameFull = "aircraft_name_full"
        }
    }
}


