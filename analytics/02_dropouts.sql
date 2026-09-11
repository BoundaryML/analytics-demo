-- Which addresses fell through, at which stage, and why.
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
)
SELECT
  error['stage']                              AS stage,
  count(*)                                    AS addresses,
  max(args['address'])                        AS example_address,
  max(error['reason'])                        AS example_reason
FROM calls
WHERE execution_id IN (SELECT execution_id FROM latest)
  AND fqn = 'user.process_address' AND status = 'errored'
GROUP BY error['stage']
ORDER BY addresses DESC;
