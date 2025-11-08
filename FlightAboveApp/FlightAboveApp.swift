import SwiftUI

@main
struct FlightAboveApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var settings = SettingsManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(settings)
        }
    }
}

