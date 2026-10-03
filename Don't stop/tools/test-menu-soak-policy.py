"""Guard the nightly continuous-session contract and its two timeout layers."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = (ROOT / '.github/workflows/deploy-pages.yml').read_text(encoding='utf-8')
DRIVER = (ROOT / "Don't stop/tools/web-menu-return-e2e.js").read_text(encoding='utf-8')


class MenuSoakPolicy(unittest.TestCase):
    def test_budget_layers_cover_20_cycles_plus_restart(self):
        gate = WORKFLOW.split('  browser-gates:', 1)[1].split('  deploy:', 1)[0]
        self.assertIn('timeout-minutes: ${{ matrix.job_budget_minutes || 8 }}', gate)
        self.assertIn('GATE_JOB_BUDGET_MINUTES: ${{ matrix.job_budget_minutes || 8 }}', gate)
        for field, soak, quick in [('job_budget_minutes', 30, 8), ('watchdog_ms', 1500000, 420000)]:
            self.assertRegex(gate, re.escape(f"{field}: ${{{{ (github.event_name == 'schedule' || inputs.menu_cycles == '20') && {soak} || {quick} }}}}"))
        # Latest historical maximum was ~50s per cycle. Include the restart,
        # two minutes of startup/reload and at least 25% run-time headroom.
        self.assertGreaterEqual(1500000, ((20 + 1) * 50 + 120) * 1000 * 1.25)
        self.assertGreaterEqual(30 * 60000 - 1500000, 5 * 60000)
        self.assertIn("export E2E_WATCHDOG_MS='${{ matrix.watchdog_ms }}'", gate)
        self.assertIn('budget=${GATE_JOB_BUDGET_MINUTES}m', gate)
        self.assertIn('if: always()', gate)
        self.assertNotIn('continue-on-error', gate)

    def test_nightly_does_not_shard_or_reduce_the_session(self):
        self.assertIn("github.event_name == 'schedule' && '20'", WORKFLOW)
        self.assertIn('for (let cycle = 1; cycle <= CYCLES; cycle++)', DRIVER)
        self.assertIn('await runCycle(CYCLES + 1, \'RESTART_AFTER_LAST_RETURN\')', DRIVER)
        self.assertIn('startedCycles === CYCLES && cleanCycles === CYCLES + 1', DRIVER)
        self.assertIn('pausedCycles === CYCLES + 1', DRIVER)
        self.assertEqual(DRIVER.count('chromium.launchPersistentContext('), 1)
        self.assertIn("phase('save-reload'", DRIVER)


if __name__ == '__main__':
    unittest.main()
