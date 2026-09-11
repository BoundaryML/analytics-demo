"""Mock address services.

Stand-in for the real geocoding / parcel / classification services. Every
endpoint is a POST that takes JSON and returns JSON. Behaviour is
deterministic per address (seeded by a hash of the input) so a re-run
produces the same answers, and each endpoint has a small artificial latency
so the profiler has something realistic to show.

    python3 server/app.py            # listens on http://127.0.0.1:8787
"""

import hashlib
import json
import random
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8787

# Street-name hints. The parcel service turns these into zoning codes (with
# some noise); the classifier uses zoning when present, otherwise keywords.
RESIDENTIAL_WORDS = {"ln", "lane", "ct", "court", "dr", "drive", "pl", "place", "ter", "cir"}
COMMERCIAL_WORDS = {"market", "commerce", "plaza", "broadway", "main", "retail"}
INDUSTRIAL_WORDS = {"industrial", "factory", "freight", "foundry", "depot", "mill"}
MIXED_WORDS = {"union", "downtown", "midtown", "station"}

ZONING_FOR = {"Residential": "R-1", "Commercial": "C-2", "Industrial": "M-1", "MixedUse": "MX-3"}
TYPE_FOR_ZONING = {v: k for k, v in ZONING_FOR.items()}

CITY_CENTERS = {
    "Springfield": (39.80, -89.65),
    "Riverton": (41.05, -111.94),
    "Fairview": (35.14, -89.92),
    "Bayside": (37.77, -122.42),
    "Hillcrest": (32.75, -117.15),
}

ADDRESS_RE = re.compile(r"^\s*(\d+[A-Z]?)\s+(.+?),\s*([A-Za-z .]+),\s*([A-Z]{2})\s+(\d{5})\s*$")


def rng_for(*parts):
    """A per-input random generator so results are stable across runs."""
    seed = hashlib.sha256("|".join(str(p) for p in parts).encode()).hexdigest()
    return random.Random(seed)


def hinted_type(street):
    words = set(street.lower().replace(".", "").split())
    if words & INDUSTRIAL_WORDS:
        return "Industrial"
    if words & MIXED_WORDS:
        return "MixedUse"
    if words & COMMERCIAL_WORDS:
        return "Commercial"
    return "Residential"


# ---------------------------------------------------------------- endpoints

def parse(body):
    m = ADDRESS_RE.match(body.get("address", ""))
    if not m:
        return 422, {"error": "unparseable address"}
    number, street, city, state, zip_code = m.groups()
    return 200, {"number": number, "street": street, "city": city.strip(), "state": state, "zip": zip_code}


def geocode(body):
    r = rng_for("geocode", body["street"], body["number"], body["city"])
    lat, lng = CITY_CENTERS.get(body["city"], (40.0, -100.0))
    point = {"lat": round(lat + r.uniform(-0.05, 0.05), 5), "lng": round(lng + r.uniform(-0.05, 0.05), 5)}
    # The primary provider is unsure about ~15% of addresses.
    confidence = r.uniform(0.3, 0.65) if r.random() < 0.15 else r.uniform(0.8, 0.99)
    return 200, {**point, "confidence": round(confidence, 2), "provider": "primary"}


def geocode_fallback(body):
    r = rng_for("fallback", body["street"], body["number"], body["city"])
    if r.random() < 0.25:
        return 404, {"error": "no match"}
    lat, lng = CITY_CENTERS.get(body["city"], (40.0, -100.0))
    return 200, {
        "lat": round(lat + r.uniform(-0.05, 0.05), 5),
        "lng": round(lng + r.uniform(-0.05, 0.05), 5),
        "confidence": round(r.uniform(0.7, 0.85), 2),
        "provider": "fallback",
    }


def parcel(body):
    r = rng_for("parcel", body["lat"], body["lng"])
    if r.random() < 0.12:
        return 404, {"error": "no parcel at this point"}
    street = body.get("street", "")
    true_type = hinted_type(street)
    # Assessor data is ~8% stale/wrong.
    zoning = ZONING_FOR[true_type] if r.random() > 0.08 else r.choice(list(ZONING_FOR.values()))
    return 200, {
        "parcel_id": f"{r.randint(100, 999)}-{r.randint(10, 99)}-{r.randint(100, 999)}",
        "zoning_code": zoning,
        "lot_sqft": r.randint(2_000, 120_000),
    }


def classify(body):
    r = rng_for("classify", body["address"])
    zoning = body.get("zoning_code")
    if zoning:
        # Zoning is a strong signal.
        return 200, {"building_type": TYPE_FOR_ZONING[zoning], "confidence": round(r.uniform(0.82, 0.98), 2)}
    # Without zoning fall back to street-name keywords: noisier, and mixed-use
    # is basically invisible to this heuristic.
    street = body["address"].split(",")[0]
    guess = hinted_type(street)
    if guess == "MixedUse":
        guess = "Commercial"
    if r.random() < 0.2:
        guess = r.choice(["Residential", "Commercial", "Industrial"])
    return 200, {"building_type": guess, "confidence": round(r.uniform(0.35, 0.8), 2)}


def enrich_residential(body):
    r = rng_for("res", body["street"], body["number"])
    return 200, {"units": r.choice([1, 1, 1, 2, 4, 12]), "year_built": r.randint(1900, 2020)}


def enrich_commercial(body):
    r = rng_for("com", body["street"], body["number"])
    name = r.choice(["Acme", "Northwind", "Contoso", "Globex", "Initech"])
    return 200, {"business_name": f"{name} {r.choice(['Cafe', 'Hardware', 'Dental', 'Books', 'Fitness'])}",
                 "naics": str(r.randint(400_000, 899_999))}


def enrich_industrial(body):
    r = rng_for("ind", body["street"], body["number"])
    return 200, {"hazmat": r.random() < 0.3, "rail_access": r.random() < 0.4}


ROUTES = {
    # path: (handler, simulated latency in seconds)
    "/v1/parse": (parse, 0.005),
    "/v1/geocode": (geocode, 0.040),
    "/v1/geocode/fallback": (geocode_fallback, 0.060),
    "/v1/parcel": (parcel, 0.025),
    "/v1/classify": (classify, 0.015),
    "/v1/enrich/residential": (enrich_residential, 0.010),
    "/v1/enrich/commercial": (enrich_commercial, 0.010),
    "/v1/enrich/industrial": (enrich_industrial, 0.010),
}


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        route = ROUTES.get(self.path)
        if route is None:
            return self._reply(404, {"error": f"no route {self.path}"})
        handler, latency = route
        length = int(self.headers.get("content-length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        time.sleep(latency)
        status, payload = handler(body)
        self._reply(status, payload)

    def _reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass  # keep the terminal quiet


if __name__ == "__main__":
    print(f"mock address services on http://127.0.0.1:{PORT}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
