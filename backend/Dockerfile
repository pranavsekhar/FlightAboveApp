# Build stage
FROM swift:5.9-focal as build

WORKDIR /build

# Copy Package files
COPY Package.swift ./
COPY Sources ./Sources
COPY Tests ./Tests

# Build
RUN swift build -c release

# Run stage
FROM swift:5.9-focal-slim

WORKDIR /app

# Copy built executable
COPY --from=build /build/.build/release/App /app/App

# Expose port
EXPOSE 8080

# Run
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]

