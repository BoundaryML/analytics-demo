# Address pipeline — BAML tracing demo

A pipeline that takes a free-text address and produces a `BuildingRecord`
(location, parcel, `Residential | Commercial | Industrial | MixedUse`, and
type-specific details) by calling a chain of POST services. Every service call
is a BAML function, so the profiler records exactly what went in and out of
each one — and `baml query` answers questions like *how many addresses reached
the parcel service* or *how accurate is classification when we had zoning data*
with plain SQL.

```
address ─► POST /v1/parse ─► POST /v1/geocode ──(low confidence)──► POST /v1/geocode/fallback
                                    │                                           │
                                    ▼◄──────────────────────────────────────────┘
                             POST /v1/parcel  (404 = no zoning hint, keep going)
                                    │
                                    ▼
                             POST /v1/classify ──(confidence < 0.5)──► dropped: needs review
                                    │
                    ┌───────────────┼─────────────────┐
                    ▼               ▼                 ▼
          /enrich/residential  /enrich/commercial  /enrich/industrial
                    └───────────────┼─────────────────┘
                                    ▼
                              BuildingRecord
```

## Layout

| | |
|---|---|
| `baml_src/types.baml` | the data shapes and the `Dropped` error |
| `baml_src/services.baml` | one function per POST endpoint; the only code that touches the network |
| `baml_src/pipeline.baml` | `process_address` — the orchestration, with `//#` annotations for the visualiser |
| `baml_src/eval.baml` | `run_eval` — runs a labelled CSV through the pipeline concurrently and scores it |
| `server/app.py` | mock services (Python stdlib, deterministic per address, small latencies) |
| `data/generate.py` | synthetic addresses with ground-truth labels; ~4% deliberately malformed |
| `analytics/*.sql` | the questions, as `baml query` SQL |
| `analytics/dashboard.py` | runs those queries and renders `dashboard.html` from `dashboard_template.html` |

## Demo

Terminal 1:

```
make server
```

Terminal 2:

### 1. One address

```
make one
# or: baml run process_address -- --address "4013 Market St, Fairview, TN 37062"
```

Then `make playground` → **Executions** → the latest run. You get the call tree
with each POST as a span, its arguments and return value, the flame graph, and
the pipeline graph drawn from `process_address`. The same thing from the CLI:

```
baml query "SELECT fqn, status, duration_ns/1000000 AS ms, args, output, error
            FROM calls ORDER BY started_at DESC LIMIT 8"
```

Try an address that falls out, and see the `Dropped` error captured on the span:

```
baml run process_address -- --address "PO Box 12"
```

### 2. One thousand addresses

```
make eval
```

```
EvalSummary {total: 1000, completed: 889, correct: 827, accuracy: 0.93,
             dropped_by_stage: {"Classify": 40, "Geocode": 33, "Parse": 38}}
```

Takes ~15s (8 addresses in flight against services that sleep 5–60 ms per call).
Now the analytics:

```
make report
```

| query | answers |
|---|---|
| `01_funnel` | how many addresses hit each POST, ok vs errored, % coverage |
| `02_dropouts` | which stage dropped how many, with an example address and reason |
| `03_accuracy` | confusion matrix of expected vs predicted building type |
| `04_accuracy_by_branch` | accuracy split by the branch taken — parcel found (94%) vs not (80%) |
| `05_latency` | p50 / p95 / max per service |
| `06_needs_review` | the low-confidence classifications, with the inputs the model saw |

`make dashboard` renders the same queries as charts in `analytics/dashboard.html`
— a static page, open it in a browser:

- a **flow diagram** of where the 1,000 addresses went (every fork in
  `process_address`, band width = addresses, drop-outs in orange) — `07_flow.sql`
- a **flame graph** of one address's call tree aggregated over the run, runtime
  frames included, from `call_path_stats` — `flame_call_tree.sql`
- KPIs, the coverage funnel, drop-outs, confusion matrix, accuracy by branch,
  latency percentiles and the review queue from queries 01–06

Query 04 is the interesting one for tracing: it joins the scoring span to the
parcel-lookup span underneath it through `parent_call_id`, i.e. the call tree
is a table you can join on.

## How the tracing works

The profiler records timing for every call automatically, but only keeps
arguments and return values for calls you ask it to. `pipeline.baml` has:

```baml
function traced() -> boundary.LocalId {
    boundary.id().capture(inputs = true, output = true, error = true)
}
```

and each service call in the pipeline passes it as call metadata:

```baml
let primary = geocode(parsed, $id = traced());
```

That is the whole integration. Everything else — `calls`, `threads`, `errors`,
`call_path_stats` — is there after any `baml run`. `baml query --schema` lists
the tables; `baml describe query` explains them.

## Notes

- `baml.env.get("SERVICES_URL")` overrides the mock server address.
- `baml test` runs the offline tests (no server needed).
- `baml clean` wipes `.baml/profiles-v1`; the report queries always look at the
  most recent `run_eval` execution.
