import Foundation

public struct FlightInfo: Codable {
    public let ident: String?
    public let identIcao: String?
    public let identIata: String?
    public let operatorCode: String?
    public let operatorIcao: String?
    public let operatorIata: String?
    public let aircraftType: String?
    public let origin: AirportInfo?
    public let destination: AirportInfo?
    
    enum CodingKeys: String, CodingKey {
        case ident
        case identIcao = "ident_icao"
        case identIata = "ident_iata"
        case operatorCode = "operator"
        case operatorIcao = "operator_icao"
        case operatorIata = "operator_iata"
        case aircraftType = "aircraft_type"
        case origin
        case destination
    }
}

public struct AirportInfo: Codable {
    public let codeIcao: String?
    public let codeIata: String?
    
    enum CodingKeys: String, CodingKey {
        case codeIcao = "code_icao"
        case codeIata = "code_iata"
    }
}

public struct AeroAPIResponse: Codable {
    public let flights: [FlightInfo]?
}

