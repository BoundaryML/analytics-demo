-- The whole call tree of the latest run, one row per call path, with
-- population-true timing. Feeds the flame graph on the dashboard (it is not
-- part of the text report: 300+ rows).
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
)
SELECT call_path_id, parent_call_path_id, depth, fqn, origin, kind, edge_kind,
       calls_started, inclusive_ns, self_ns, await_ns
FROM call_path_stats
WHERE execution_id IN (SELECT execution_id FROM latest) AND overflow_reason IS NULL
ORDER BY depth, inclusive_ns DESC;
