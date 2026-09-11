-- Accuracy of the classifier on the addresses that made it through:
-- a confusion matrix of expected vs. predicted building type.
WITH latest AS (
  SELECT execution_id FROM threads
  WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
  ORDER BY started_at DESC LIMIT 1
),
scored AS (
  SELECT args['row']['expected'] AS expected, output['predicted'] AS predicted, output['correct'] AS correct
  FROM calls
  WHERE execution_id IN (SELECT execution_id FROM latest)
    AND fqn = 'user.evaluate' AND output['dropped_at'] IS NULL
)
SELECT
  expected,
  count(*)                                                        AS addresses,
  sum(CASE WHEN correct THEN 1 ELSE 0 END)                        AS correct,
  round(100.0 * sum(CASE WHEN correct THEN 1 ELSE 0 END) / count(*), 1) AS accuracy_pct,
  sum(CASE WHEN predicted = 'Residential' THEN 1 ELSE 0 END)      AS as_residential,
  sum(CASE WHEN predicted = 'Commercial' THEN 1 ELSE 0 END)       AS as_commercial,
  sum(CASE WHEN predicted = 'Industrial' THEN 1 ELSE 0 END)       AS as_industrial,
  sum(CASE WHEN predicted = 'MixedUse' THEN 1 ELSE 0 END)         AS as_mixed_use
FROM scored
GROUP BY expected
ORDER BY addresses DESC;
