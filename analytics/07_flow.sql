-- Every branch in the pipeline as an edge with a count, for the flow diagram:
-- which way did each address go at each decision point?
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
),
c AS (
  SELECT fqn, output FROM calls WHERE execution_id IN (SELECT execution_id FROM latest)
)
SELECT 'parsed'             AS edge, count(*) AS addresses FROM c WHERE fqn = 'user.parse_address'     AND output['number'] IS NOT NULL
UNION ALL SELECT 'unparseable',        count(*) FROM c WHERE fqn = 'user.parse_address'     AND output['number'] IS NULL
UNION ALL SELECT 'geocode_confident',  count(*) FROM c WHERE fqn = 'user.geocode'           AND output['confidence'] >= 0.7
UNION ALL SELECT 'geocode_low',        count(*) FROM c WHERE fqn = 'user.geocode'           AND output['confidence'] < 0.7
UNION ALL SELECT 'fallback_matched',   count(*) FROM c WHERE fqn = 'user.geocode_fallback'  AND output['lat'] IS NOT NULL
UNION ALL SELECT 'fallback_none',      count(*) FROM c WHERE fqn = 'user.geocode_fallback'  AND output['lat'] IS NULL
UNION ALL SELECT 'parcel_found',       count(*) FROM c WHERE fqn = 'user.lookup_parcel'     AND output['parcel_id'] IS NOT NULL
UNION ALL SELECT 'parcel_none',        count(*) FROM c WHERE fqn = 'user.lookup_parcel'     AND output['parcel_id'] IS NULL
UNION ALL SELECT 'classify_confident', count(*) FROM c WHERE fqn = 'user.classify_building' AND output['confidence'] >= 0.5
UNION ALL SELECT 'classify_review',    count(*) FROM c WHERE fqn = 'user.classify_building' AND output['confidence'] < 0.5
UNION ALL SELECT 'enrich_residential', count(*) FROM c WHERE fqn = 'user.enrich_residential'
UNION ALL SELECT 'enrich_commercial',  count(*) FROM c WHERE fqn = 'user.enrich_commercial'
UNION ALL SELECT 'enrich_industrial',  count(*) FROM c WHERE fqn = 'user.enrich_industrial';
