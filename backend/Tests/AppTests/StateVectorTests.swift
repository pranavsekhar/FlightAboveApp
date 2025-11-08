import XCTest
@testable import App

final class StateVectorTests: XCTestCase {
    
    func testStateVectorParsing() {
        // Sample OpenSky state vector array (17 elements)
        let array: [Any?] = [
            "a1b2c3",           // 0: icao24
            "UAL456",            // 1: callsign
            "United States",    // 2: origin_country
            1234567890,          // 3: time_position
            1234567890,          // 4: last_contact
            -122.4194,           // 5: lon
            37.7749,             // 6: lat
            10000.0,             // 7: baro_altitude
            false,               // 8: on_ground
            250.0,               // 9: velocity
            180.0,               // 10: heading
            0.0,                 // 11: vertical_rate
            [1, 2],              // 12: sensors
            10500.0,             // 13: geo_altitude
            "1234",              // 14: squawk
            false,               // 15: spi
            0                    // 16: position_source
        ]
        
        let stateVector = StateVector(from: array)
        
        XCTAssertNotNil(stateVector)
        XCTAssertEqual(stateVector?.icao24, "a1b2c3")
        XCTAssertEqual(stateVector?.callsign, "UAL456")
        XCTAssertEqual(stateVector?.lat, 37.7749)
        XCTAssertEqual(stateVector?.lon, -122.4194)
        XCTAssertEqual(stateVector?.geoAltitude, 10500.0)
    }
    
    func testStateVectorParsingWithEmptyCallsign() {
        let array: [Any?] = [
            "a1b2c3",
            "",                  // Empty callsign
            "United States",
            1234567890,
            1234567890,
            -122.4194,
            37.7749,
            10000.0,
            false,
            250.0,
            180.0,
            0.0,
            nil,
            10500.0,
            nil,
            false,
            0
        ]
        
        let stateVector = StateVector(from: array)
        
        XCTAssertNotNil(stateVector)
        XCTAssertNil(stateVector?.callsign)
    }
    
    func testStateVectorParsingInsufficientElements() {
        let array: [Any?] = ["a1b2c3", "UAL456"] // Only 2 elements
        
        let stateVector = StateVector(from: array)
        
        XCTAssertNil(stateVector)
    }
}

