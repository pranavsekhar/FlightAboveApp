import XCTest
@testable import App

final class GeoTests: XCTestCase {
    
    func testHaversineDistance() {
        // San Francisco to New York (approximately 4139 km)
        let sfLat = 37.7749
        let sfLon = -122.4194
        let nyLat = 40.7128
        let nyLon = -74.0060
        
        let distance = Geo.haversineKm(lat1: sfLat, lon1: sfLon, lat2: nyLat, lon2: nyLon)
        XCTAssertEqual(distance, 4139, accuracy: 50, "Distance should be approximately 4139 km")
    }
    
    func testHaversineSamePoint() {
        let lat = 37.7749
        let lon = -122.4194
        
        let distance = Geo.haversineKm(lat1: lat, lon1: lon, lat2: lat, lon2: lon)
        XCTAssertEqual(distance, 0, accuracy: 0.001, "Distance to same point should be 0")
    }
    
    func testBearing() {
        // North from origin
        let bearing = Geo.computeBearingDeg(lat1: 0, lon1: 0, lat2: 1, lon2: 0)
        XCTAssertEqual(bearing, 0, accuracy: 1, "Bearing north should be approximately 0°")
        
        // East from origin
        let bearingEast = Geo.computeBearingDeg(lat1: 0, lon1: 0, lat2: 0, lon2: 1)
        XCTAssertEqual(bearingEast, 90, accuracy: 1, "Bearing east should be approximately 90°")
    }
    
    func testBoundingBox() {
        let lat = 37.7749
        let lon = -122.4194
        let radiusKm = 10.0
        
        let bbox = Geo.centeredBoundingBox(lat: lat, lon: lon, radiusKm: radiusKm)
        
        XCTAssertLessThan(bbox.latMin, lat)
        XCTAssertGreaterThan(bbox.latMax, lat)
        XCTAssertLessThan(bbox.lonMin, lon)
        XCTAssertGreaterThan(bbox.lonMax, lon)
    }
    
    func testElevationAngle() {
        // Aircraft at 10km altitude, 10km ground distance
        let elev = Geo.computeElevationDeg(aircraftAltM: 10000, userAltM: 0, groundDistanceKm: 10)
        XCTAssertEqual(elev, 45, accuracy: 1, "45° elevation for equal altitude and distance")
        
        // Aircraft directly overhead (very close ground distance)
        let elevOverhead = Geo.computeElevationDeg(aircraftAltM: 10000, userAltM: 0, groundDistanceKm: 0.1)
        XCTAssertGreaterThan(elevOverhead, 89, "Should be near 90° for overhead aircraft")
    }
    
    func testUnitConversions() {
        let meters = 1000.0
        let feet = Geo.metersToFeet(meters)
        XCTAssertEqual(feet, 3280.84, accuracy: 0.1)
        
        let km = 100.0
        let nm = Geo.kmToNauticalMiles(km)
        XCTAssertEqual(nm, 53.9957, accuracy: 0.1)
        
        let ms = 100.0
        let kt = Geo.msToKnots(ms)
        XCTAssertEqual(kt, 194.384, accuracy: 0.1)
    }
}

