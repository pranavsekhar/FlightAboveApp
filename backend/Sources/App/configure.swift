import Vapor
import AsyncHTTPClient

public func configure(_ app: Application) async throws {
    // Configure HTTP client with longer timeouts for Render/cloud environments
    // Default is 10s connect timeout, which can be too short for some networks
    app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
        connect: .seconds(30),  // 30 seconds to establish connection
        read: .seconds(60)      // 60 seconds to read response
    )
    
    // Register routes
    try routes(app)
    
    // Configure CORS - in production, restrict to your app's origin
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,  // Change to .custom("https://your-app-origin.com") in production
        allowedMethods: [.GET],
        allowedHeaders: [.accept, .contentType],
        allowCredentials: false
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    app.middleware.use(cors, at: .beginning)
}
