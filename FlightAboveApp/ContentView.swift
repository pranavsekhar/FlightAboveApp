import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        NavigationView {
            SettingsView()
                .navigationTitle("Flight Above")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        Form {
            Section(header: Text("Location")) {
                if locationManager.authorizationStatus == .notDetermined {
                    Button("Request Location Permission") {
                        locationManager.requestPermission()
                    }
                } else if locationManager.authorizationStatus == .denied {
                    Text("Location permission denied. Please enable in Settings.")
                        .foregroundColor(.red)
                } else {
                    if let location = locationManager.currentLocation {
                        Text("Lat: \(location.coordinate.latitude, specifier: "%.4f")")
                        Text("Lon: \(location.coordinate.longitude, specifier: "%.4f")")
                    } else {
                        Text("Getting location...")
                    }
                }
            }
            
            Section(header: Text("Search Radius")) {
                Picker("Radius", selection: $settings.radiusKm) {
                    Text("30 km").tag(30.0)
                    Text("60 km").tag(60.0)
                    Text("90 km").tag(90.0)
                    Text("120 km").tag(120.0)
                }
            }
            
            Section(header: Text("Elevation Filter")) {
                Toggle("Strict overhead only (≥75°)", isOn: $settings.strictOverhead)
            }
            
            Section(header: Text("Backend URL")) {
                TextField("Backend URL", text: $settings.backendURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            }
        }
    }
}

