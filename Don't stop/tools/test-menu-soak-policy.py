"""Guard the monthly continuous-session contract and its two timeout layers."""
import pathlib
import re
import json
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / '.github/workflows/deploy-pages.yml').read_text(encoding='utf-8')
DRIVER = (ROOT / "Don't stop/tools/web-menu-return-e2e.js").read_text(encoding='utf-8')


class MenuSoakPolicy(unittest.TestCase):
    def test_budget_layers_cover_20_cycles_plus_restart(self):
        gate = WORKFLOW.split('  browser-gates:', 1)[1].split('  deploy:', 1)[0]
        expression = re.search(r'timeout-minutes: \$\{\{ (.+) \}\}', gate).group(1)
        self.assertIn('GATE_JOB_BUDGET_MINUTES: ${{ ' + expression + ' }}', gate)
        budget = re.fullmatch(r"matrix.name == '([^']+)' && (\d+) \|\| matrix.name == '([^']+)' && (\d+) \|\| matrix.job_budget_minutes \|\| (\d+)", expression)
        self.assertIsNotNone(budget)
        special = {budget.group(1): int(budget.group(2)), budget.group(3): int(budget.group(4))}
        fallback = int(budget.group(5))
        for name, matrix_budget, expected in [('menu-return', 30, 30), ('menu-return', 8, 8), ('stages-fair', 12, 12), ('smoke', None, 8), ('save-audit', None, 30)]:
            resolved = special.get(name, matrix_budget or fallback)
            self.assertEqual(resolved, expected, name)
        for field, soak, quick in [('job_budget_minutes', 30, 8), ('watchdog_ms', 1500000, 420000)]:
            self.assertRegex(gate, re.escape(f"{field}: ${{{{ (github.event_name == 'schedule' || github.event_name == 'release' || inputs.menu_cycles == '20') && {soak} || {quick} }}}}"))
        # Latest historical maximum was ~50s per cycle. Include the restart,
        # two minutes of startup/reload and at least 25% run-time headroom.
        self.assertGreaterEqual(1500000, ((20 + 1) * 50 + 120) * 1000 * 1.25)
        self.assertGreaterEqual(30 * 60000 - 1500000, 5 * 60000)
        self.assertIn("export E2E_WATCHDOG_MS='${{ matrix.watchdog_ms }}'", gate)
        self.assertIn('budget=${GATE_JOB_BUDGET_MINUTES}m', gate)
        self.assertIn('if: always()', gate)
        self.assertNotIn('continue-on-error', gate)

    def test_full_save_gate_does_not_expand_the_pr_matrix(self):
        gate = WORKFLOW.split('  browser-gates:', 1)[1].split('  deploy:', 1)[0]
        names = re.search(r"github.event_name == 'pull_request' && '([^']+)' \|\| '([^']+)'", gate)
        self.assertEqual(json.loads(names.group(1)), ['smoke', 'menu-return'])
        self.assertIn('save-audit', json.loads(names.group(2)))
        self.assertNotIn('- name: save-audit', gate)
        self.assertIn('tools/web-save-durable.js', gate)
        self.assertNotIn('- name: stages-fair', gate)

    def test_monthly_does_not_shard_or_reduce_the_session(self):
        self.assertIn("(github.event_name == 'schedule' || github.event_name == 'release') && '20'", WORKFLOW)
        self.assertIn('for (let cycle = 1; cycle <= CYCLES; cycle++)', DRIVER)
        self.assertIn('await runCycle(CYCLES + 1, \'RESTART_AFTER_LAST_RETURN\')', DRIVER)
        self.assertIn('startedCycles === CYCLES && cleanCycles === CYCLES + 1', DRIVER)
        self.assertIn('pausedCycles === CYCLES + 1', DRIVER)
        self.assertEqual(DRIVER.count('chromium.launchPersistentContext('), 1)
        self.assertIn("phase('save-reload'", DRIVER)


if __name__ == '__main__':
    unittest.main()
