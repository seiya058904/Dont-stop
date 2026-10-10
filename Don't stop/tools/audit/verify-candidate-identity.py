"""Isolated orchestration test for the real verify.py --candidate guard.

No Godot is started and no project file is modified.  native_shard is replaced
only to record the exact bytes delivered past the candidate identity guard.
The other main(), manifest, digest, and clone logic are the production source.
An exit of 1 means at least one mismatched candidate reached the native runner.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd() / "Don't stop/tools/verify.py"
spec = importlib.util.spec_from_file_location("verify_candidate_under_audit", source)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)

results = []
real_check_output = verify.subprocess.check_output
for scenario in ("matching", "candidate_script_changed", "candidate_product_added",
                 "candidate_product_missing", "checkout_product_added", "checkout_product_missing",
                 "wrong_engine_release", "different_engine_build", "mutable_docs_and_generated_evidence",
                 "fresh_matching", "fresh_untracked_product", "fresh_staged_product"):
    with tempfile.TemporaryDirectory(prefix="dont-stop-verify-identity-") as directory:
        root = Path(directory)
        checkout = root / "checkout"
        candidate = root / "prepared/candidate"
        for directory_path in (checkout, candidate):
            (directory_path / "tools").mkdir(parents=True)
            (directory_path / "tools/native-cases.json").write_text("{}", encoding="utf-8")
            (directory_path / "runtime.gd").write_text("extends Node\nconst REVISION = 1\n", encoding="utf-8")
        preparation = {
            "commit": "baseline-audit-fixture",
            "engine_version": "4.7.2.stable.official.fixture",
            "source_sha256": {"runtime.gd": verify.digest(checkout / "runtime.gd")},
        }
        (candidate.parent / "preparation.json").write_text(json.dumps(preparation), encoding="utf-8")
        if scenario == "candidate_script_changed":
            (candidate / "runtime.gd").write_text("extends Node\nconst REVISION = 2\n", encoding="utf-8")
        if scenario == "candidate_product_added":
            (candidate / "additional_runtime.gd").write_text("extends Node\n", encoding="utf-8")
        if scenario == "candidate_product_missing":
            (candidate / "runtime.gd").unlink()
        if scenario == "checkout_product_added":
            (checkout / "additional_runtime.gd").write_text("extends Node\n", encoding="utf-8")
        if scenario == "checkout_product_missing":
            (checkout / "runtime.gd").unlink()
        if scenario == "mutable_docs_and_generated_evidence":
            for directory_path in (checkout, candidate):
                (directory_path / "docs").mkdir()
                (directory_path / "docs/audit.md").write_text(str(directory_path), encoding="utf-8")
            (candidate / "evidence").mkdir()
            (candidate / "evidence/generated.json").write_text("{}", encoding="utf-8")
        if scenario.startswith("fresh_"):
            # Exercise the REAL copy_candidate/git-ls-files boundary using a
            # temporary local index. --imported skips any engine import; this
            # fixture cache marker is never delivered as engine evidence.
            (checkout / "tools/verify.py").write_text("# isolated fixture tool placeholder\n", encoding="utf-8")
            (checkout / ".godot").mkdir()
            (checkout / ".godot/candidate-sha").write_text(preparation["commit"] + "\n", encoding="utf-8")
            verify.subprocess.run(["git", "init", "-q", str(root)], check=True, capture_output=True)
            verify.subprocess.run(["git", "add", "--", "checkout/runtime.gd", "checkout/tools/verify.py",
                                   "checkout/tools/native-cases.json"], cwd=root, check=True, capture_output=True)
            if scenario in ("fresh_untracked_product", "fresh_staged_product"):
                (checkout / "additional_runtime.gd").write_text("extends Node\n", encoding="utf-8")
            if scenario == "fresh_staged_product":
                verify.subprocess.run(["git", "add", "--", "checkout/additional_runtime.gd"],
                                      cwd=root, check=True, capture_output=True)

        verify.PROJECT = checkout
        verify.ROOT = root
        verify.revision = lambda: preparation["commit"]
        verify.targeted = lambda _base: ["audit-no-engine"]
        observed = {}
        engine_checks = []
        engine_version = preparation["engine_version"]
        if scenario == "wrong_engine_release":
            engine_version = "4.6.1.stable.official.fixture"
        elif scenario == "different_engine_build":
            engine_version = "4.7.2.stable.custom.other-build"

        def engine_version_adapter(args, *positional, **keywords):
            if args == ["audit-engine", "--version"]:
                engine_checks.append(engine_version)
                return engine_version + "\n"
            return real_check_output(args, *positional, **keywords)

        verify.subprocess.check_output = engine_version_adapter

        def capture_native(project, engine, _out, _ids):
            observed.update(
                reached_native_runner=True,
                delivered_sha256=verify.digest(project / "runtime.gd") if (project / "runtime.gd").is_file() else None,
                checkout_sha256=verify.digest(checkout / "runtime.gd") if (checkout / "runtime.gd").is_file() else None,
                extra_checkout_file_exists=(checkout / "additional_runtime.gd").exists(),
                extra_delivered_file_exists=(project / "additional_runtime.gd").exists(),
                engine_received=engine,
            )
            return {"success": True, "note": "stub; no Godot test executed"}

        verify.native_shard = capture_native
        sys.argv = [str(source), "verify-fast", "--out", str(root / "result"), "--godot", "audit-engine"]
        sys.argv += ["--imported"] if scenario.startswith("fresh_") else ["--candidate", str(candidate)]
        try:
            return_code = verify.main()
            accepted = True
            reason = ""
        except (RuntimeError, FileNotFoundError) as error:
            return_code = None
            accepted = False
            reason = str(error)
        mismatch = scenario not in ("matching", "mutable_docs_and_generated_evidence", "fresh_matching", "fresh_staged_product")
        results.append({
            "scenario": scenario,
            "candidate_identity_guard_accepted": accepted,
            "main_return_code_with_stub_runner": return_code,
            "guard_rejection": reason,
            "contract_holds": accepted != mismatch,
            "engine_version_checks": engine_checks,
            **observed,
        })

print(json.dumps({"source": str(source), "no_engine_executed": True, "results": results}, indent=2))
raise SystemExit(0 if all(result["contract_holds"] for result in results) else 1)
