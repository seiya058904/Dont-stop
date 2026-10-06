"""Pins coverage, failure propagation and artifact ownership during CI refactors."""
import importlib.util
import json
from pathlib import Path
import re
import shlex
import subprocess
import unittest

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]
spec = importlib.util.spec_from_file_location('verification', TOOLS / 'verify.py')
verification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verification)


class VerificationPolicy(unittest.TestCase):
    def test_exact_release_case_set_and_arguments(self):
        original = subprocess.check_output(['git', 'show', 'v1.3.5:.github/workflows/native-tests.yml'], cwd=ROOT, text=True, encoding='utf-8')
        for group, expected_count in [('contracts', 58), ('pressure', 6)]:
            part = original.split(f'  {group}:', 1)[1].split('\n  ' + ('pressure:' if group == 'contracts' else 'historical-evidence:'), 1)[0]
            expected = [shlex.split(c) for c in re.findall(r'^          run_case ([A-Za-z0-9].*)$', part, re.M)]
            actual = verification.MANIFEST['groups'][group]
            self.assertEqual(len(actual['cases']), expected_count)
            self.assertCountEqual([[c['scene'], *c['args']] for c in actual['cases']], expected)
            assigned = [c for s in actual['shards'] for c in s['cases']]
            self.assertCountEqual(assigned, [c['id'] for c in actual['cases']])
            self.assertEqual(len(assigned), len(set(assigned)))
        self.assertEqual(sum(c['min_checks'] for c in verification.CASES.values()), 3707)

    def test_fail_closed_on_partial_exit_script_error_or_missing_marker(self):
        case = dict(min_checks=2, completion_marker='^COMPLETE$')
        good = 'PASS one\nPASS two\nCOMPLETE\n'
        self.assertTrue(verification.assess(case, 0, good)['success'])
        for code, content in [(124, good), (1, good), (0, good + 'FAIL broken\n'), (0, good + 'SCRIPT ERROR broken\n'), (0, good.replace('PASS two\n', '')), (0, good.replace('COMPLETE\n', ''))]:
            self.assertFalse(verification.assess(case, code, content)['success'])

    def test_all_shards_are_required_and_import_identity_is_checked(self):
        workflow = (ROOT / '.github/workflows/native-tests.yml').read_text(encoding='utf-8')
        active = workflow.split('  contracts:', 1)[1].split('  historical-evidence:', 1)[0]
        self.assertNotIn('continue-on-error', active)
        self.assertEqual(active.count('fail-fast: false'), 2)
        self.assertIn('needs: [setup, contracts, pressure]', active)
        self.assertIn('test "$CONTRACTS" = success && test "$PRESSURE" = success', active)
        self.assertEqual(active.count('candidate-sha'), 2)
        for shard in verification.SHARDS:
            self.assertIn(shard, active)
        # Source/cache/user profiles are intentionally absent from uploaded evidence.
        self.assertNotIn('/candidate\n', active)
        self.assertNotIn('/userdata', active)

    def test_real_time_long_runs_remain_complete(self):
        m6 = verification.CASES['M6EncounterAudit']
        m8 = verification.CASES['M8Encounters']
        self.assertIn('rows=30', m6['completion_marker'])
        self.assertIn('checks=60', m8['completion_marker'])
        self.assertEqual((m6['timeout_seconds'], m8['timeout_seconds']), (1800, 2400))
        source = (TOOLS / 'verify.py').read_text(encoding='utf-8')
        self.assertNotIn('--quit-after', source)
        self.assertNotIn('--time-scale', source)
        self.assertIn('APPDATA=str(directory)', source)
        self.assertIn('XDG_DATA_HOME=str(directory)', source)

    def test_main_builds_once_and_waits_for_fast_browser_gates(self):
        workflow = (ROOT / '.github/workflows/deploy-pages.yml').read_text(encoding='utf-8')
        self.assertEqual(workflow.count('--export-release "Web Release"'), 1)
        gate = workflow.split('  browser-gates:', 1)[1].split('  deploy:', 1)[0]
        self.assertIn("github.event_name == 'pull_request' || github.event_name == 'push'", gate)
        self.assertIn('["smoke","menu-return"]', gate)
        self.assertNotIn('--export-release', gate)
        deploy = workflow.split('  deploy:', 1)[1]
        self.assertIn('needs: [build, browser-gates, web-required-gate]', deploy)
        self.assertIn("needs.browser-gates.result == 'success'", deploy)
        self.assertNotIn("needs.browser-gates.result == 'skipped'", deploy)
        self.assertIn('Verify production SHA and every payload byte', deploy)
        full_gate = workflow.split('  web-required-gate:', 1)[1].split('  browser-gates:', 1)[0]
        self.assertIn('if: always()', full_gate)
        self.assertNotIn("if: always() && github.event_name == 'pull_request'", full_gate)

    def test_durable_assertions_and_faults_are_unchanged(self):
        original = subprocess.check_output(['git', 'show', "v1.3.5:Don't stop/tools/web-save-durable.js"], cwd=ROOT, text=True, encoding='utf-8')
        current = (TOOLS / 'web-save-durable.js').read_text(encoding='utf-8')
        # All semantic code is unchanged except diagnostic timing/screenshots.
        normalise = lambda s: re.sub(r'\s+', '', re.sub(r'await (?:page\.screenshot\(\{ path: path\.join\(out, (.*?)\) \}\)|screenshot\((.*?)\))\s*;', '', s))
        # Compare the test body, excluding the new diagnostic helper and finally timing.
        old = original.split(' async function until(', 1)[1].split(' finally {', 1)[0]
        new = current.split(' async function until(', 1)[1].split(' finally {', 1)[0]
        self.assertEqual(normalise(old), normalise(new))
        self.assertIn("await page.screenshot({ path: path.join(out, 'failure.png') })", current)


if __name__ == '__main__':
    unittest.main()
