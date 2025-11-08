import Foundation
import Combine

class SettingsManager: ObservableObject {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.flightabove.app") ?? UserDefaults.standard
    
    @Published var radiusKm: Double {
        didSet {
            sharedDefaults.set(radiusKm, forKey: "radiusKm")
        }
    }
    
    @Published var strictOverhead: Bool {
        didSet {
            sharedDefaults.set(strictOverhead, forKey: "strictOverhead")
        }
    }
    
    @Published var backendURL: String {
        didSet {
            sharedDefaults.set(backendURL, forKey: "backendURL")
        }
    }
    
    init() {
        self.radiusKm = sharedDefaults.object(forKey: "radiusKm") as? Double ?? 60.0
        self.strictOverhead = sharedDefaults.bool(forKey: "strictOverhead")
        self.backendURL = sharedDefaults.string(forKey: "backendURL") ?? "http://localhost:8080"
    }
}
