"""Read the six real Dart JSON reporter streams, never expected test counts."""
import json
import os
from pathlib import Path

root = Path("build/pine_audit")
root.mkdir(parents=True, exist_ok=True)
groups = {}
for name in ["main", *[f"extra_{i}" for i in range(1, 6)]]:
    path = root / f"{name}.jsonl"
    results = {}
    complete = False
    success = None
    if path.exists():
        for line in path.read_text().splitlines():
            event = json.loads(line)
            if event["type"] == "testDone":
                results[event["testID"]] = (
                    None if event["hidden"] else
                    "failed" if event["result"] != "success" else
                    "skipped" if event["skipped"] else "passed"
                )
            elif event["type"] == "error" and event["testID"] in results:
                # Late errors after testDone count as failure (including hidden).
                results[event["testID"]] = "failed"
            elif event["type"] == "done":
                success = event["success"]
                complete = success is not None
    groups[name] = dict(
        completed=complete, success=success,
        **{k: sum(v == k for v in results.values())
           for k in ("passed", "failed", "skipped")}
    )
summary = {
    "run_id": os.environ.get("GITHUB_RUN_ID"),
    "git_sha": os.environ.get("GITHUB_SHA"),
    "source": "Dart JSON reporter testDone and late error events",
    "completed": all(g["completed"] for g in groups.values()),
    "groups": groups,
    **{k: sum(g[k] for g in groups.values()) for k in ("passed", "failed", "skipped")}
}
(root / "ci_test_totals.json").write_text(json.dumps(summary, indent=2) + "\n")
audit_path = root / "ahv10_full_diagnostics.json"
audit = json.loads(audit_path.read_text()) if audit_path.exists() else None
if audit:
    counts = audit["counts"]
    assert counts["total"] == len(audit["diagnostics"])
    for category in ("type_error", "unresolved_name", "other_error",
                     "known_unimplemented", "unsupported_notice", "other_notice"):
        assert counts[category] == sum(d["category"] == category for d in audit["diagnostics"])
    print("PINE_FULL_COUNTS " + json.dumps(counts))
print("PINE_CI_TOTALS " + json.dumps(summary))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
    f.write("## Flutter test totals (actual JSON events)\n\n")
    f.write("| Passed | Failed | Skipped | Complete |\n|---:|---:|---:|---|\n")
    f.write(f"| {summary['passed']} | {summary['failed']} | {summary['skipped']} | {summary['completed']} |\n")
    if audit:
        f.write("\n## AHV10 complete diagnostic census\n\n")
        f.write(f"Fixture SHA-256: `{audit['fixture_sha256']}`\n\n")
        f.write("| Category | Count |\n|---|---:|\n")
        for k, v in audit["counts"].items():
            f.write(f"| {k} | {v} |\n")
    else:
        f.write("\nAHV10 evidence not produced; do not treat missing data as zero.\n")
if not summary["completed"] or not audit or not audit["counts"]["completed"]:
    raise SystemExit("Incomplete audit or test streams")
