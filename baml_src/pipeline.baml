// The pipeline: one address in, one BuildingRecord out (or a Dropped error
// saying which stage gave up on it).

/// Attach to a call to record its arguments, return value and error in the
/// profile store, so `baml query` can see exactly what went through it.
function traced() -> boundary.LocalId {
    boundary.id().capture(inputs = true, output = true, error = true)
}

function dropped(stage: Stage, reason: string) -> never {
    throw Dropped { stage: stage, reason: reason };
}

//   baml run process_address -- --address "4013 Market St, Fairview, TN 37062"
function process_address(address: string) -> BuildingRecord {
    //# Stage 1: parse free text into components
    let parsed = parse_address(address, $id = traced()) ?? dropped(Stage.Parse, "address could not be parsed");
    //# Stage 2: geocode; a low-confidence hit is retried through the fallback provider
    let primary = geocode(parsed, $id = traced());
    let point = if (primary.confidence >= 0.7) {
        primary
    } else {
        //# fallback geocoder
        geocode_fallback(parsed, $id = traced())
            ?? dropped(Stage.Geocode, `primary confidence ${primary.confidence}, fallback had no match`)
    };
    //# Stage 3: parcel lookup is best-effort — no parcel just means no zoning hint
    let parcel = lookup_parcel(point, parsed, $id = traced());
    //# Stage 4: classify the building, with zoning when we have it
    let classification = classify_building(
        ClassifyRequest {
            address: address,
            zoning_code: parcel?.zoning_code,
            lot_sqft: parcel?.lot_sqft,
        },
        $id = traced(),
    );
    if (classification.confidence < 0.5) {
        dropped(Stage.Classify, `confidence ${classification.confidence} is below 0.5, needs review`);
    }
    //# Stage 5: enrichment depends on the building type
    let details = match (classification.building_type) {
        BuildingType.Residential => enrich_residential(parsed, $id = traced()),
        BuildingType.Commercial | BuildingType.MixedUse => enrich_commercial(parsed, $id = traced()),
        BuildingType.Industrial => enrich_industrial(parsed, $id = traced()),
    };

    BuildingRecord {
        address: address,
        location: point,
        parcel: parcel,
        building_type: classification.building_type,
        confidence: classification.confidence,
        details: details,
    }
}
