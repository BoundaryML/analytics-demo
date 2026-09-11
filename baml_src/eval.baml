// Batch evaluation: run every labelled address through the pipeline and
// score it. The scoring span (`evaluate`) is traced too, so expected vs.
// predicted lives in the profile store next to the pipeline spans.

class LabeledAddress {
    address: string,
    expected: BuildingType,
}

class EvalResult {
    address: string,
    expected: BuildingType,
    predicted: BuildingType?,
    correct: bool,
    dropped_at: Stage?,
    reason: string?,
}

function evaluate(row: LabeledAddress) -> EvalResult {
    let outcome: BuildingRecord | Dropped = process_address(row.address, $id = traced()) catch (e) {
        Dropped => e
    };

    match (outcome) {
        let record: BuildingRecord => {
            EvalResult {
                address: row.address,
                expected: row.expected,
                predicted: record.building_type,
                correct: record.building_type == row.expected,
                dropped_at: null,
                reason: null,
            }
        },
        let drop: Dropped => {
            EvalResult {
                address: row.address,
                expected: row.expected,
                predicted: null,
                correct: false,
                dropped_at: drop.stage,
                reason: drop.reason,
            }
        },
    }
}

class EvalSummary {
    total: int,
    completed: int,
    correct: int,
    accuracy: float,
    dropped_by_stage: map<string, int>,
}

//   baml run run_eval
//   baml run run_eval -- --path data/addresses.csv --concurrency 4
function run_eval(path: string = "data/addresses.csv", concurrency: int = 8) -> EvalSummary {
    //# Load the labelled addresses
    let rows = baml.csv.decode<LabeledAddress>(baml.fs.read(path));
    //# Run every address through the pipeline, `concurrency` at a time
    let pool = baml.spawn.TaskGroup.new(concurrency, name = "addresses");
    let futures = rows.map((row) -> {
        spawn with baml.spawn.options(group = pool) { evaluate(row, $id = traced()) }
    });
    let results = await baml.future.all(futures);
    //# Roll up
    summarize(results)
}

function summarize(results: EvalResult[]) -> EvalSummary {
    let completed = results.filter((r) -> {
        r.dropped_at == null
    });
    let correct = results.filter((r) -> {
        r.correct
    });
    let dropped_by_stage: map<string, int> = {};
    for (let r in results) {
        if let stage: Stage = r.dropped_at {
            let key = stage.to_string();
            dropped_by_stage.set(key, (dropped_by_stage.get(key) ?? 0) + 1);
        }
    }
    EvalSummary {
        total: results.length(),
        completed: completed.length(),
        correct: correct.length(),
        accuracy: correct.length() / (completed.length() * 1.0),
        dropped_by_stage: dropped_by_stage,
    }
}

test "summarize counts drops and scores only completed rows" {
    let ok = EvalResult {
        address: "a",
        expected: BuildingType.Residential,
        predicted: BuildingType.Residential,
        correct: true,
        dropped_at: null,
        reason: null,
    };
    let wrong = EvalResult { ...ok, address: "b", predicted: BuildingType.Commercial, correct: false };
    let dropped = EvalResult {
        ...ok,
        address: "c",
        predicted: null,
        correct: false,
        dropped_at: Stage.Parse,
        reason: "unparseable",
    };
    let summary = summarize([ok, wrong, dropped, dropped]);
    assert.equal(summary.total, 4);
    assert.equal(summary.completed, 2);
    assert.equal(summary.correct, 1);
    assert.approx_equal(summary.accuracy, 0.5, 0.001);
    assert.equal(summary.dropped_by_stage.get("Parse"), 2)
}
