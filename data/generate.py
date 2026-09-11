"""Generate synthetic labelled addresses.

    python3 data/generate.py 1000 > data/addresses.csv

Each row is `address,expected` where `expected` is the ground-truth building
type. Street names carry the hints the mock services key off; a few percent
of rows are deliberately malformed so the parse stage has something to drop.
"""

import random
import sys

STREETS = {
    "Residential": ["Maple Ln", "Oak Dr", "Willow Ct", "Birch Pl", "Cedar Ter", "Elm Cir", "Aspen Dr"],
    "Commercial": ["Market St", "Commerce Blvd", "Main St", "Broadway", "Plaza Way", "Retail Row"],
    "Industrial": ["Industrial Pkwy", "Factory Rd", "Freight Way", "Foundry Ave", "Depot St", "Mill Rd"],
    "MixedUse": ["Union Sq", "Downtown Ave", "Midtown St", "Station Blvd"],
}
WEIGHTS = {"Residential": 55, "Commercial": 25, "Industrial": 12, "MixedUse": 8}
CITIES = [("Springfield", "IL", "62701"), ("Riverton", "UT", "84065"), ("Fairview", "TN", "37062"),
          ("Bayside", "CA", "94110"), ("Hillcrest", "CA", "92103")]
MALFORMED = ["PO Box {n}", "{street}", "{n} {street}", "Apt 4B", "N/A", ""]


def main(count):
    r = random.Random(42)
    print("address,expected")
    for _ in range(count):
        kind = r.choices(list(WEIGHTS), weights=list(WEIGHTS.values()))[0]
        street = r.choice(STREETS[kind])
        city, state, zip_code = r.choice(CITIES)
        n = r.randint(1, 9999)
        if r.random() < 0.04:
            address = r.choice(MALFORMED).format(n=n, street=street)
        else:
            address = f"{n} {street}, {city}, {state} {zip_code}"
        print(f'"{address}",{kind}')


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 1000)
