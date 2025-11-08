import WidgetKit
import SwiftUI
import CoreLocation

struct FlightAboveWidget: Widget {
    let kind: String = "FlightAboveWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlightTimelineProvider()) { entry in
            FlightAboveWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Flight Above")
        .description("Shows aircraft directly overhead")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FlightAboveWidgetEntryView: View {
    var entry: FlightEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.aircraft.isEmpty {
                VStack {
                    Text("No flights directly overhead")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(entry.aircraft.prefix(3))) { aircraft in
                    VStack(alignment: .leading, spacing: 2) {
                        // Title: Airline or "Flight" · CALLSIGN
                        HStack {
                            Text(aircraft.airline ?? "Flight")
                                .font(.headline)
                                .lineLimit(1)
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(aircraft.callsign ?? "N/A")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        
                        // Subtitle: aircraft_name_short or aircraft_type origin→destination
                        HStack {
                            Text(aircraft.aircraftNameShort ?? aircraft.aircraftType ?? "Unknown")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let origin = aircraft.originIcao,
                               let dest = aircraft.destinationIcao {
                                Text("\(origin)→\(dest)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .lineLimit(1)
                    }
                }
            }
        }
        .padding()
    }
}

struct FlightEntry: TimelineEntry {
    let date: Date
    let aircraft: [AboveResponse.Aircraft]
    let error: String?
}

struct FlightTimelineProvider: TimelineProvider {
    typealias Entry = FlightEntry
    
    func placeholder(in context: Context) -> Entry {
        FlightEntry(
            date: Date(),
            aircraft: [],
            error: nil
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let entry = FlightEntry(
            date: Date(),
            aircraft: [],
            error: nil
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let settings = SettingsManager()
        let backendURL = settings.backendURL
        let radiusKm = settings.radiusKm
        
        // For widget, we need to use a location manager that can work in widget context
        // In practice, widgets should request location via AppIntent or use last known location
        // For now, we'll use a default location (user should set this in app)
        // In production, consider using App Groups to share location between app and widget
        
        // Try to get location from shared defaults or use a default
        let sharedDefaults = UserDefaults(suiteName: "group.com.flightabove.app")
        let lat = sharedDefaults?.double(forKey: "lastLat") ?? 37.7749  // Default to SF
        let lon = sharedDefaults?.double(forKey: "lastLon") ?? -122.4194
        
        // Fetch from backend
        let urlString = "\(backendURL)/above?lat=\(lat)&lon=\(lon)&radius_km=\(radiusKm)"
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else {
            let entry = FlightEntry(
                date: Date(),
                aircraft: [],
                error: "Invalid URL"
            )
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
            completion(timeline)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            var entry: Entry
            
            if let error = error {
                entry = FlightEntry(
                    date: Date(),
                    aircraft: [],
                    error: error.localizedDescription
                )
            } else if let data = data {
                do {
                    let response = try JSONDecoder().decode(AboveResponse.self, from: data)
                    entry = FlightEntry(
                        date: Date(),
                        aircraft: response.aircraft,
                        error: response.errors?.first
                    )
                } catch {
                    entry = FlightEntry(
                        date: Date(),
                        aircraft: [],
                        error: "Parse error: \(error.localizedDescription)"
                    )
                }
            } else {
                entry = FlightEntry(
                    date: Date(),
                    aircraft: [],
                    error: "No data"
                )
            }
            
            // Refresh every 30 minutes
            let nextUpdate = Date().addingTimeInterval(30 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }.resume()
    }
}

