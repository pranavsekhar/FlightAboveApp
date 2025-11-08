# Flight Above Backend

Swift Vapor backend for the "What's Above Me" iOS widget.

## Environment Variables

Required:
- `OPENSKY_ID` - OpenSky Network OAuth client ID
- `OPENSKY_SECRET` - OpenSky Network OAuth client secret
- `AEROAPI_KEY` - FlightAware AeroAPI key

Optional:
- `LOOKUP_CDN_BASE` - Base URL for lookup CDN (e.g., https://cdn.example.com)
- `PORT` - Server port (default: 8080)

## Running

```bash
swift run App serve --env production --hostname 0.0.0.0 --port 8080
```

## Docker

```bash
docker build -t flight-above-backend .
docker run -p 8080:8080 \
  -e OPENSKY_ID=your_id \
  -e OPENSKY_SECRET=your_secret \
  -e AEROAPI_KEY=your_key \
  flight-above-backend
```

## API Endpoint

### GET /above

Query parameters:
- `lat` (required): Latitude
- `lon` (required): Longitude
- `radius_km` (optional): Search radius in kilometers (default: 60, min: 10, max: 120)

Returns JSON with aircraft directly overhead (elevation >= 70°).

