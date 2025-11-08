import Foundation

// Shared settings manager for widget (non-observable version)
class SettingsManager {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.flightabove.app") ?? UserDefaults.standard
    
    var radiusKm: Double {
        return sharedDefaults.object(forKey: "radiusKm") as? Double ?? 60.0
    }
    
    var strictOverhead: Bool {
        return sharedDefaults.bool(forKey: "strictOverhead")
    }
    
    var backendURL: String {
        return sharedDefaults.string(forKey: "backendURL") ?? "http://localhost:8080"
    }
}

