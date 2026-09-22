"""Small affected-test loop. L3 stays in the existing B19 candidate runners.

GODOT=<pinned executable> python tools/b194-local.py L1
GODOT=... python tools/b194-local.py L2 --url http://127.0.0.1:8199/index.html
No export, installation, screenshot or trace is performed by this runner.
"""
from b194_import_check import validate as validate_import

import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = [
    (r"B11Stress|B194Pressure", ["B194Pressure"], [], False),
    (r"Hero.gd|TacticalEnemy|EnemyBarrage|BossUltimate|HostileZone|ArenaHazards|B194Combat|CombatStatus|DemoHUD|CampPanel|autoload/Demo.gd",
     ["B194Combat"], ["B11Fairness", "B8Contracts"], False),
    (r"web/|boot/|autoload/(Utils|Warmup)|ui/MainUI|web-b193|smoke-web|menu-return",
     ["B17Contracts"], ["B19Contracts"], True),
    (r"bullets/|EnemyShot|MechanismProjectile|CombatArena|game/diag/",
     ["B192Safety", "B19Contracts"], ["B192Spawn", "B191Runtime"], False),
    (r"PlayerData|Save|save|migration", ["B12Save"], ["M11SaveMigration"], False),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tier", choices=["L1", "L2"])
    parser.add_argument("--godot", default=os.environ.get("GODOT"))
    parser.add_argument("--url", help="Existing immutable Web build; export once before L2")
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--details", action="store_true")
    args = parser.parse_args()
    if not args.godot or not Path(args.godot).is_file():
        parser.error("Set GODOT or --godot to the existing pinned Godot 4.7.2 executable")
    changed = subprocess.check_output(
        ["git", "diff", "--name-only", args.base, "--"], cwd=ROOT, text=True,
        encoding="utf-8").splitlines()
    suites = ["BaselineRegression", "B194Contracts"]
    web = False
    for pattern, direct, regression, needs_web in RULES:
        if any(re.search(pattern, p) for p in changed):
            suites.extend(direct)
            if args.tier == "L2":
                suites.extend(regression)
            web |= needs_web
    suites = list(dict.fromkeys(suites))
    if args.tier == "L2" and web and not args.url:
        parser.error("Affected Web L2 requires --url for the already exported candidate")
    out = ROOT / "output" / "b19-4" / (args.tier.lower() + "-" + time.strftime("%Y%m%d-%H%M%S"))
    out.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    budget = 120 if args.tier == "L1" else 300
    rows = []

    def run(name, command, contract=False, env=None):
        begin = time.monotonic()
        remaining = budget - (begin - started)
        if remaining <= 0:
            rows.append({"name": name, "ok": False, "error": "tier budget exhausted"})
            return False
        try:
            proc = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, timeout=remaining)
            output = proc.stdout.decode("utf-8", errors="replace")
            checks = len(re.findall(r"^PASS ", output, re.M))
            errors = (validate_import(output, ROOT) if name == "import" else
                      re.findall(r"^(?:SCRIPT ERROR:|ERROR:|FAIL ).*$", output, re.M))
            ok = proc.returncode == 0 and not errors and (not contract or checks > 0)
            row = {"name": name, "wall_ms": round((time.monotonic()-begin)*1000),
                   "exit": proc.returncode, "checks": checks, "ok": ok, "errors": errors}
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b"").decode("utf-8", errors="replace")
            row = {"name": name, "wall_ms": round((time.monotonic()-begin)*1000),
                   "ok": False, "error": "tier budget exceeded"}
            ok = False
        if not ok or args.details:
            (out / (name + ".log")).write_text(output, encoding="utf-8")
        rows.append(row)
        print(json.dumps(row), flush=True)
        return ok

    ok = run("import", [args.godot, "--headless", "--path", str(ROOT), "--import", "--quit"])
    for suite in suites:
        if not ok:
            break
        ok = run(suite, [args.godot, "--headless", "--path", str(ROOT),
                        "res://tests/" + suite + ".tscn"], contract=True)
    if ok and args.tier == "L2" and web:
        env = dict(os.environ, B194_RUNS="1", B194_EVIDENCE="0", E2E_SCREENSHOTS="none")
        for script, extra in [("web-b193-startup", []), ("smoke-web", []),
                              ("web-menu-return-e2e", ["1"])]:
            evidence = out / script
            evidence.mkdir()
            if not run(script, ["node", str(ROOT / "tools" / (script + ".js")),
                                args.url, str(evidence), *extra], env=env):
                ok = False
                break
    elapsed = round((time.monotonic()-started)*1000)
    report = {"tier": args.tier, "changed_paths": changed, "suites": suites,
              "steps": rows, "wall_ms": elapsed, "budget_ms": budget*1000,
              "ok": ok and elapsed <= budget*1000, "formal_performance_acceptance": False}
    (out / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"report": str(out / "summary.json"), "wall_ms": elapsed, "ok": report["ok"]}))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
