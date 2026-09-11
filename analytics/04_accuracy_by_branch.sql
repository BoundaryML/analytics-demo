-- Does the branch an address took change accuracy? Join the scoring span to
-- the parcel lookup underneath it (evaluate -> process_address -> lookup_parcel)
-- to split accuracy by "had zoning data" vs "classified from the address alone".
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
),
scored AS (
  SELECT call_id, output['correct'] AS correct
  FROM calls
  WHERE execution_id IN (SELECT execution_id FROM latest)
    AND fqn = 'user.evaluate' AND output['dropped_at'] IS NULL
),
pipeline AS (
  SELECT call_id, parent_call_id FROM calls
  WHERE execution_id IN (SELECT execution_id FROM latest) AND fqn = 'user.process_address'
),
parcel AS (
  SELECT parent_call_id, output['parcel_id'] IS NOT NULL AS found FROM calls
  WHERE execution_id IN (SELECT execution_id FROM latest) AND fqn = 'user.lookup_parcel'
)
SELECT
  CASE WHEN parcel.found THEN 'zoning from parcel' ELSE 'no parcel: address heuristics' END AS branch,
  count(*)                                                                  AS addresses,
  round(100.0 * sum(CASE WHEN scored.correct THEN 1 ELSE 0 END) / count(*), 1) AS accuracy_pct
FROM scored
JOIN pipeline ON pipeline.parent_call_id = scored.call_id
JOIN parcel   ON parcel.parent_call_id = pipeline.call_id
GROUP BY parcel.found
ORDER BY addresses DESC;
