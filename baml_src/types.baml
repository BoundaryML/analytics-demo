// What the pipeline produces, and the shapes each service speaks.

enum BuildingType {
    Residential,
    Commercial,
    Industrial,
    MixedUse,
}

class ParsedAddress {
    number: string,
    street: string,
    city: string,
    state: string,
    zip: string,
}

class GeoPoint {
    lat: float,
    lng: float,
    confidence: float,
    provider: string,
}

class Parcel {
    parcel_id: string,
    zoning_code: string,
    lot_sqft: int,
}

class Classification {
    building_type: BuildingType,
    confidence: float,
}

class ResidentialInfo {
    units: int,
    year_built: int,
}

class CommercialInfo {
    business_name: string,
    naics: string,
}

class IndustrialInfo {
    hazmat: bool,
    rail_access: bool,
}

type Enrichment = ResidentialInfo | CommercialInfo | IndustrialInfo;

/// The finished record for one address.
class BuildingRecord {
    address: string,
    location: GeoPoint,
    parcel: Parcel?,
    building_type: BuildingType,
    confidence: float,
    details: Enrichment,
}

/// Where an address fell out of the pipeline.
enum Stage {
    Parse,
    Geocode,
    Classify,
}

/// Thrown when an address cannot make it through a stage.
class Dropped {
    stage: Stage,
    reason: string,
}
