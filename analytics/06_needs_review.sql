-- The review queue: addresses the classifier was unsure about, with the
-- inputs and confidence it saw, ready to hand to a person.
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
)
SELECT
  args['request']['address']      AS address,
  args['request']['zoning_code']  AS zoning_code,
  output['building_type']         AS guessed,
  output['confidence']            AS confidence
FROM calls
WHERE execution_id IN (SELECT execution_id FROM latest)
  AND fqn = 'user.classify_building' AND output['confidence'] < 0.5
ORDER BY output['confidence']
LIMIT 10;
