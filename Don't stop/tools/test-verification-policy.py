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


# These are the only reviewed source migrations from the published durable
# fixture: optional screenshots/timing, and the real slow-write scheduler.
# Compare the WHOLE script. Splitting at the first `finally` stopped inside
# independentRead() and silently left every executed assertion unprotected.
DURABLE_GRACE_SCHEDULE = """     // Schedule the fault's real write inside the slow confirmation window.
     // A 7 s timer alone can correctly confirm before the asserted 10 s floor.
     // This anchor follows verify.call, so its clock starts after the verifier.
     const commitNotBefore = performance.now() + 10000;
     const commitInGrace = () => {
      const remaining = commitNotBefore - performance.now();
      if (remaining > 0) {
       window.towdownSave.record('slow-fixture-commit-wait', { remaining_ms: remaining, minimum_delay_ms: 10000 });
       window.setTimeout(commitInGrace, Math.ceil(remaining));
       return;
      }
      commitSlowSnapshot();
     };
     window.setTimeout(commitInGrace, slowVisibilityDelayMs);"""
DURABLE_SCREENSHOT_HELPER = """ async function screenshot(name) {
  if (process.env.E2E_SCREENSHOTS !== 'none') await page.screenshot({ path: path.join(out, name) });
 }
"""


def durable_contract_source(source, current=False):
    source = source.replace('\r\n', '\n')
    if current:
        report_declaration = ' const lines = [], rects = {}, report = { checks: [] };\n'
        page_declaration = ' let page = await context.newPage();\n'
        migrations = [
            (' const runStarted = Date.now();\n' + report_declaration, report_declaration),
            (DURABLE_SCREENSHOT_HELPER + page_declaration, page_declaration),
            (' finally { report.wall_clock_ms = Date.now() - runStarted; fs.writeFileSync', ' finally { fs.writeFileSync'),
            (DURABLE_GRACE_SCHEDULE, '     window.setTimeout(commitSlowSnapshot, slowVisibilityDelayMs);'),
        ]
        for argument in ["fault + '-failed.png'", "'original-downloaded.png'", "'ds001-pending-blocked.png'",
                         "fault + '-first-save-discard.png'", "fault + '-after-discard.png'"]:
            migrations.append(('await screenshot(' + argument + ');',
                               'await page.screenshot({ path: path.join(out, ' + argument + ') });'))
        for old, new in migrations:
            if source.count(old) != 1:
                raise ValueError('Expected exactly one reviewed durable fixture migration: ' + old.splitlines()[0])
            source = source.replace(old, new, 1)
    # Keep all body whitespace, including string literals, and every screenshot
    # argument. Removing them can hide a disabled fault or an early process exit.
    # Adjacent anchors also prevent a reviewed declaration from moving scope.
    return source.rstrip('\n')


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
        self.assertEqual(durable_contract_source(original), durable_contract_source(current, current=True))
        self.assertIn("await page.screenshot({ path: path.join(out, 'failure.png') })", current)

    def test_durable_guard_rejects_changed_assertions_faults_and_scheduler(self):
        current = (TOOLS / 'web-save-durable.js').read_text(encoding='utf-8')
        accepted = durable_contract_source(current, current=True)
        changes = [
            ('diagnostic.callback.elapsed_ms >= 10000', 'diagnostic.callback.elapsed_ms >= 0'),
            ('diagnostic.callback.elapsed_ms < 18000', 'diagnostic.callback.elapsed_ms < 99999'),
            ('fixtureDelay === 7000', 'fixtureDelay === -1'),
            ('match.elapsed_ms >= 10000', 'match.elapsed_ms >= 0'),
            ('window.__nativeIDBPut.call(store, row, path);', 'void 0;'),
            ("if (window.saveFault === 'abort') this.transaction.abort();", 'void 0;'),
            ("if (window.saveFault === 'quota') throw new DOMException('Injected full storage', 'QuotaExceededError');", 'void 0;'),
            ("window.saveFault === 'abort'", "window.saveFault === 'ab ort'"),
            ("check(camp.rank === 0 && carry.gold === 9999,", 'check(true,'),
            ("check(camp.rank === 0, fault + ': full-page reload remains a fresh session');", "check(true, fault + ': full-page reload remains a fresh session');"),
        ]
        for old, new in changes:
            with self.subTest(mutation=old):
                self.assertIn(old, current)
                self.assertNotEqual(accepted, durable_contract_source(current.replace(old, new, 1), current=True))
        for mutation in [
            current.replace(DURABLE_GRACE_SCHEDULE, '', 1),
            current + '\n' + DURABLE_GRACE_SCHEDULE,
            current.replace('const commitNotBefore = performance.now() + 10000;', 'const commitNotBefore = performance.now() + 7000;', 1),
        ]:
            with self.subTest(scheduler_migration='missing, duplicate or altered'):
                with self.assertRaises(ValueError):
                    durable_contract_source(mutation, current=True)
        relocated = current.replace(DURABLE_GRACE_SCHEDULE, '', 1) + '\n' + DURABLE_GRACE_SCHEDULE
        self.assertNotEqual(accepted, durable_contract_source(relocated, current=True))
        for block in [
            ' const runStarted = Date.now();\n',
            DURABLE_SCREENSHOT_HELPER,
            'report.wall_clock_ms = Date.now() - runStarted; ',
        ]:
            with self.subTest(relocated_reviewed_block=block.splitlines()[0]):
                relocated = current.replace(block, '', 1) + '\n' + block
                with self.assertRaises(ValueError):
                    durable_contract_source(relocated, current=True)
        screenshot_side_effect = current.replace("await screenshot(fault + '-failed.png');",
                                                 "await screenshot((process.exit(0), fault + '-failed.png'));", 1)
        with self.assertRaises(ValueError):
            durable_contract_source(screenshot_side_effect, current=True)


if __name__ == '__main__':
    unittest.main()
