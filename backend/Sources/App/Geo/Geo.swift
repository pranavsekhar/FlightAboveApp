import Foundation

public struct Geo {
    private static let earthRadiusKm = 6371.0
    private static let metersToFeet = 3.28084
    private static let kmToNauticalMiles = 0.539957
    
    // Convert degrees to radians
    public static func degreesToRadians(_ deg: Double) -> Double {
        return deg * .pi / 180.0
    }
    
    // Convert radians to degrees
    public static func radiansToDegrees(_ rad: Double) -> Double {
        return rad * 180.0 / .pi
    }
    
    // Haversine distance in kilometers
    public static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dlat = degreesToRadians(lat2 - lat1)
        let dlon = degreesToRadians(lon2 - lon1)
        let a = sin(dlat / 2) * sin(dlat / 2) +
                cos(degreesToRadians(lat1)) * cos(degreesToRadians(lat2)) *
                sin(dlon / 2) * sin(dlon / 2)
        let c = 2 * asin(sqrt(a))
        return earthRadiusKm * c
    }
    
    // Initial bearing in degrees (0-360)
    public static func computeBearingDeg(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dlon = degreesToRadians(lon2 - lon1)
        let lat1r = degreesToRadians(lat1)
        let lat2r = degreesToRadians(lat2)
        let x = sin(dlon) * cos(lat2r)
        let y = cos(lat1r) * sin(lat2r) - sin(lat1r) * cos(lat2r) * cos(dlon)
        let initial = atan2(x, y)
        let deg = fmod((radiansToDegrees(initial) + 360.0), 360.0)
        return deg
    }
    
    // Compute bounding box around a center point
    public static func centeredBoundingBox(
        lat: Double,
        lon: Double,
        radiusKm: Double
    ) -> (latMin: Double, latMax: Double, lonMin: Double, lonMax: Double) {
        let latDelta = radiusKm / 111.0
        let lonDelta = radiusKm / (111.0 * cos(degreesToRadians(lat)))
        let latMin = lat - latDelta
        let latMax = lat + latDelta
        let lonMin = lon - lonDelta
        let lonMax = lon + lonDelta
        return (latMin, latMax, lonMin, lonMax)
    }
    
    // Compute elevation angle in degrees
    // aircraftAltM: aircraft altitude in meters
    // userAltM: user altitude in meters (default 0)
    // groundDistanceKm: ground distance in kilometers
    public static func computeElevationDeg(
        aircraftAltM: Double,
        userAltM: Double = 0.0,
        groundDistanceKm: Double
    ) -> Double {
        let groundDistanceM = groundDistanceKm * 1000.0
        let altDiffM = aircraftAltM - userAltM
        let elevRad = atan2(altDiffM, groundDistanceM)
        return radiansToDegrees(elevRad)
    }
    
    // Convert meters to feet
    public static func metersToFeet(_ meters: Double) -> Double {
        return meters * metersToFeet
    }
    
    // Convert kilometers to nautical miles
    public static func kmToNauticalMiles(_ km: Double) -> Double {
        return km * kmToNauticalMiles
    }
    
    // Convert m/s to knots
    public static func msToKnots(_ ms: Double) -> Double {
        return ms * 1.94384
    }
}

