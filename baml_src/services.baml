// One BAML function per POST endpoint. These are the only places that touch
// the network, so tracing them gives a complete picture of what each service
// saw and returned.

class ServiceError {
    path: string,
    status: int,
    body: string,
}

function base_url() -> string {
    baml.env.get("SERVICES_URL") ?? "http://127.0.0.1:8787"
}

/// POST `body` as JSON and decode the reply as `T`. Non-2xx throws ServiceError.
function post<T>(path: string, body: unknown) -> T {
    let response = baml.http.send(
        baml.http.Request {
            method: "POST",
            url: `${base_url()}${path}`,
            headers: { "content-type": "application/json" },
            body: baml.json.to_string(body),
        },
    );
    if (!response.ok()) {
        throw ServiceError { path: path, status: response.status_code, body: response.text() };
    }
    baml.json.from_string<T>(response.text())
}

/// Like `post`, but a 404 / 422 means "no answer" rather than a failure.
function post_or_null<T>(path: string, body: unknown) -> T? {
    post<T>(path, body) catch (e) {
        ServiceError { status: 404 | 422 } => null,
    }
}

class ParseRequest {
    address: string,
}

class ClassifyRequest {
    address: string,
    zoning_code: string?,
    lot_sqft: int?,
}

/// POST /v1/parse — split free text into components; null if unparseable.
function parse_address(address: string) -> ParsedAddress? {
    post_or_null<ParsedAddress>("/v1/parse", ParseRequest { address: address })
}

/// POST /v1/geocode — primary geocoder. Always answers, but not always confidently.
function geocode(parsed: ParsedAddress) -> GeoPoint {
    post<GeoPoint>("/v1/geocode", parsed)
}

/// POST /v1/geocode/fallback — slower second provider; null when it has no match either.
function geocode_fallback(parsed: ParsedAddress) -> GeoPoint? {
    post_or_null<GeoPoint>("/v1/geocode/fallback", parsed)
}

class ParcelRequest {
    lat: float,
    lng: float,
    street: string,
}

/// POST /v1/parcel — county assessor lookup; null when no parcel covers the point.
function lookup_parcel(point: GeoPoint, parsed: ParsedAddress) -> Parcel? {
    post_or_null<Parcel>(
        "/v1/parcel",
        ParcelRequest { lat: point.lat, lng: point.lng, street: parsed.street },
    )
}

/// POST /v1/classify — building-type model. Uses zoning when we have it.
function classify_building(request: ClassifyRequest) -> Classification {
    post<Classification>("/v1/classify", request)
}

/// POST /v1/enrich/* — type-specific detail lookups.
function enrich_residential(parsed: ParsedAddress) -> ResidentialInfo {
    post<ResidentialInfo>("/v1/enrich/residential", parsed)
}

function enrich_commercial(parsed: ParsedAddress) -> CommercialInfo {
    post<CommercialInfo>("/v1/enrich/commercial", parsed)
}

function enrich_industrial(parsed: ParsedAddress) -> IndustrialInfo {
    post<IndustrialInfo>("/v1/enrich/industrial", parsed)
}
