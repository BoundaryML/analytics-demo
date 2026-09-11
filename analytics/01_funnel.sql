-- Coverage: how many addresses reached each POST, and how each call ended.
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
),
total AS (
  SELECT count(*) AS addresses FROM calls
  WHERE execution_id IN (SELECT execution_id FROM latest) AND fqn = 'user.process_address'
)
SELECT
  fqn                                                        AS step,
  count(*)                                                   AS calls,
  sum(CASE WHEN status = 'ok' THEN 1 ELSE 0 END)             AS ok,
  sum(CASE WHEN status = 'errored' THEN 1 ELSE 0 END)        AS errored,
  round(100.0 * count(*) / (SELECT addresses FROM total), 1) AS pct_of_addresses,
  round(avg(duration_ns) / 1e6, 1)                           AS avg_ms
FROM calls
WHERE execution_id IN (SELECT execution_id FROM latest)
  AND fqn LIKE 'user.%' AND fqn NOT IN ('user.evaluate', 'user.run_eval')
GROUP BY fqn
ORDER BY calls DESC;
