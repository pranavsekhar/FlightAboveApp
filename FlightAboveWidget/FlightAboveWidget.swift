import WidgetKit
import SwiftUI
import CoreLocation
import AppIntents

struct FlightAboveWidget: Widget {
    let kind: String = "FlightAboveWidget"
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FlightNavigationIntent.self, provider: FlightTimelineProvider()) { entry in
            FlightAboveWidgetEntryView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Flight Above")
        .description("Shows aircraft directly overhead. Swipe up/down to navigate.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FlightAboveWidgetEntryView: View {
    var entry: FlightEntry
    
    @AppStorage("currentFlightIndex", store: UserDefaults(suiteName: "group.com.flightabove.app")) 
    private var currentFlightIndex: Int = 0
    
    var body: some View {
        ZStack {
            // LED wall background - dark
            Color.black
                .ignoresSafeArea()
            
            if entry.aircraft.isEmpty {
                VStack {
                    LEDText(text: "NO FLIGHTS OVERHEAD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show only one flight at a time
                // Wrap index if out of bounds (handle negative indices)
                let count = entry.aircraft.count
                let wrappedIndex = ((currentFlightIndex % count) + count) % count
                let aircraft = entry.aircraft[wrappedIndex]
                
                LEDSingleFlightView(
                    aircraft: aircraft, 
                    currentIndex: wrappedIndex + 1, 
                    totalCount: entry.aircraft.count
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

struct LEDSingleFlightView: View {
    let aircraft: AboveResponse.Aircraft
    let currentIndex: Int
    let totalCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Route (IATA codes) - top line, most prominent
            if let origin = aircraft.originIata ?? aircraft.originIcao,
               let dest = aircraft.destinationIata ?? aircraft.destinationIcao {
                LEDText(text: "\(origin) > \(dest)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            // Aircraft model (full name preferred, fallback to short)
            if let aircraftModel = aircraft.aircraftNameFull ?? aircraft.aircraftNameShort ?? aircraft.aircraftType {
                LEDText(text: aircraftModel.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            // Airline name and flight number
            HStack(spacing: 4) {
                LEDText(text: aircraft.airline?.uppercased() ?? "FLIGHT")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                
                if let callsign = aircraft.callsign {
                    LEDText(text: callsign.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            Spacer()
            
            // Airport names at bottom (matching LED wall screenshot)
            if let originName = aircraft.originName {
                LEDText(text: originName.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            if let destName = aircraft.destinationName {
                LEDText(text: destName.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Stats row - bottom
            HStack(spacing: 12) {
                if let speed = aircraft.gsKt {
                    LEDText(text: "SPD \(Int(speed)) KT")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let alt = aircraft.altFt {
                    LEDText(text: "ALT \(Int(alt)) FT")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Flight counter and navigation hints (subtle, bottom right)
            if totalCount > 1 {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        LEDText(text: "\(currentIndex)/\(totalCount)")
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        
                        // Navigation hint
                        LEDText(text: "SWIPE ↑↓")
                            .font(.system(size: 7, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Custom view to create pixelated LED effect
struct LEDText: View {
    let text: String
    var font: Font = .system(size: 12, weight: .bold, design: .monospaced)
    var foregroundColor: Color = .white
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(foregroundColor)
            .tracking(0.5) // Slight letter spacing for LED look
            .shadow(color: foregroundColor.opacity(0.3), radius: 1, x: 0, y: 0) // Subtle glow
            .lineLimit(1)
            .minimumScaleFactor(0.8) // Prevent text from being cut off
    }
}

// App Intent for widget configuration (required for AppIntentConfiguration)
struct FlightNavigationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Flight Above"
    static var description = IntentDescription("Shows aircraft directly overhead")
}

// App Intents for widget interactive buttons
struct NextFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Flight"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flightabove.app")
        let currentIndex = sharedDefaults?.integer(forKey: "currentFlightIndex") ?? 0
        // Don't wrap here - let the view handle wrapping
        sharedDefaults?.set(currentIndex + 1, forKey: "currentFlightIndex")
        WidgetCenter.shared.reloadTimelines(ofKind: "FlightAboveWidget")
        return .result()
    }
}

struct PreviousFlightIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Flight"
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult {
        let sharedDefaults = UserDefaults(suiteName: "group.com.flightabove.app")
        let currentIndex = sharedDefaults?.integer(forKey: "currentFlightIndex") ?? 0
        // Decrement - the view will handle wrapping
        sharedDefaults?.set(currentIndex - 1, forKey: "currentFlightIndex")
        WidgetCenter.shared.reloadTimelines(ofKind: "FlightAboveWidget")
        return .result()
    }
}

struct FlightEntry: TimelineEntry {
    let date: Date
    let aircraft: [AboveResponse.Aircraft]
    let error: String?
}

struct FlightTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = FlightEntry
    typealias Intent = FlightNavigationIntent
    
    func placeholder(in context: Context) -> Entry {
        FlightEntry(
            date: Date(),
            aircraft: [],
            error: nil
        )
    }
    
    func snapshot(for configuration: FlightNavigationIntent, in context: Context) async -> Entry {
        FlightEntry(
            date: Date(),
            aircraft: [],
            error: nil
        )
    }
    
    func timeline(for configuration: FlightNavigationIntent, in context: Context) async -> Timeline<Entry> {
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
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            var entry: Entry
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                entry = FlightEntry(
                    date: Date(),
                    aircraft: [],
                    error: "HTTP \(httpResponse.statusCode)"
                )
            } else {
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
            }
            
            // Refresh every 30 minutes
            let nextUpdate = Date().addingTimeInterval(30 * 60)
            return Timeline(entries: [entry], policy: .after(nextUpdate))
        } catch {
            let entry = FlightEntry(
                date: Date(),
                aircraft: [],
                error: error.localizedDescription
            )
            // Refresh every 5 minutes on error
            let nextUpdate = Date().addingTimeInterval(5 * 60)
            return Timeline(entries: [entry], policy: .after(nextUpdate))
        }
    }
}

