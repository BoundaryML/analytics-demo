"""Build analytics/dashboard.html from the profile store.

    python3 analytics/dashboard.py          # or: make dashboard

Runs each query in this directory through `baml query --format json`, plus one
for the run itself, and drops the results into dashboard_template.html as a
JSON blob. The page draws its own charts; no server, no dependencies.
"""

import json
import pathlib
import subprocess

HERE = pathlib.Path(__file__).parent
RUN_SQL = """
SELECT execution_id, started_at, duration_ns, total_calls, calls_retained, threads_total
FROM threads
WHERE parent_thread_id IS NULL AND entry_fqn = 'user.run_eval'
ORDER BY started_at DESC LIMIT 1
"""


def query(sql):
    out = subprocess.run(["baml", "query", "-", "--format", "json"], input=sql, capture_output=True, text=True)
    if not out.stdout:
        raise SystemExit(out.stderr or "baml query produced no output")
    return json.loads(out.stdout)["rows"]


def main():
    data = {"run": query(RUN_SQL)[0]}
    for sql in sorted(HERE.glob("0*.sql")):
        key = sql.stem.split("_", 1)[1]          # 01_funnel.sql -> funnel
        data[key] = query(sql.read_text())
    data["call_tree"] = query((HERE / "flame_call_tree.sql").read_text())
    template = (HERE / "dashboard_template.html").read_text()
    html = template.replace("__DATA__", json.dumps(data, indent=1))
    (HERE / "dashboard.html").write_text(html)
    print(f"wrote {HERE / 'dashboard.html'} for run {data['run']['execution_id'][14:26]}")


if __name__ == "__main__":
    main()
