import Foundation

public struct StateVector: Codable {
    public let icao24: String
    public let callsign: String?
    public let originCountry: String?
    public let timePosition: Int?
    public let lastContact: Int?
    public let lon: Double?
    public let lat: Double?
    public let baroAltitude: Double?
    public let onGround: Bool?
    public let velocity: Double?
    public let heading: Double?
    public let verticalRate: Double?
    public let sensors: [Int]?
    public let geoAltitude: Double?
    public let squawk: String?
    public let spi: Bool?
    public let positionSource: Int?
    
    enum CodingKeys: String, CodingKey {
        case icao24
        case callsign
        case originCountry = "origin_country"
        case timePosition = "time_position"
        case lastContact = "last_contact"
        case lon
        case lat
        case baroAltitude = "baro_altitude"
        case onGround = "on_ground"
        case velocity
        case heading
        case verticalRate = "vertical_rate"
        case sensors
        case geoAltitude = "geo_altitude"
        case squawk
        case spi
        case positionSource = "position_source"
    }
    
    // Parse from OpenSky array format (17 elements)
    public init?(from array: [Any]) {
        guard array.count >= 17 else { return nil }
        
        self.icao24 = (array[0] as? String) ?? ""
        self.callsign = {
            if let cs = array[1] as? String, !cs.isEmpty {
                return cs.trimmingCharacters(in: .whitespaces)
            }
            return nil
        }()
        self.originCountry = array[2] as? String
        self.timePosition = array[3] as? Int
        self.lastContact = array[4] as? Int
        self.lon = array[5] as? Double
        self.lat = array[6] as? Double
        self.baroAltitude = array[7] as? Double
        self.onGround = array[8] as? Bool
        self.velocity = array[9] as? Double
        self.heading = array[10] as? Double
        self.verticalRate = array[11] as? Double
        if array.count > 12, let sensorsValue = array[12] as? Int {
            self.sensors = [sensorsValue]
        } else if array.count > 12, let sensorsArray = array[12] as? [Int] {
            self.sensors = sensorsArray
        } else {
            self.sensors = nil
        }
        self.geoAltitude = array[13] as? Double
        self.squawk = array[14] as? String
        self.spi = array[15] as? Bool
        self.positionSource = array[16] as? Int
    }
}


