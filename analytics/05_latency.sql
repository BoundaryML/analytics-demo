-- Where the time goes: latency percentiles per service.
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
)
SELECT
  fqn                                                              AS step,
  count(*)                                                         AS calls,
  round(approx_percentile_cont(duration_ns, 0.5) / 1e6, 1)         AS p50_ms,
  round(approx_percentile_cont(duration_ns, 0.95) / 1e6, 1)        AS p95_ms,
  round(max(duration_ns) / 1e6, 1)                                 AS max_ms
FROM calls
WHERE execution_id IN (SELECT execution_id FROM latest)
  AND fqn LIKE 'user.%' AND fqn NOT IN ('user.evaluate', 'user.run_eval')
GROUP BY fqn
ORDER BY p50_ms DESC;
