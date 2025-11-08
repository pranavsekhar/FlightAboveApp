import Vapor

public func configure(_ app: Application) async throws {
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
