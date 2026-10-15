import copy
import json
import pathlib
import unittest

from scripts.sdlc_fleet import (
    FleetContractError,
    secret_actions,
    verify_check_runs,
    verify_consumer_pin,
    verify_ruleset,
)


ROOT = pathlib.Path(__file__).parent / "fixtures" / "sdlc-fleet"
PLAN = json.loads((ROOT / "plan.json").read_text())
RULESET = json.loads((ROOT / "ruleset.json").read_text())
CHECK_RUNS = json.loads((ROOT / "check-runs.json").read_text())
LOCK = json.loads((ROOT / "consumer-lock.json").read_text())
FLAKE = (ROOT / "consumer-flake.nix").read_text()


class FleetContractTests(unittest.TestCase):
    def test_first_apply_plan_has_real_required_checks(self):
        self.assertEqual(PLAN["action"], "create")
        verify_check_runs(PLAN, CHECK_RUNS)

    def test_onboarded_noop_readback(self):
        verify_ruleset(PLAN, RULESET, "blogle/anvil")

    def test_drift_repair_is_detected_by_readback(self):
        drifted = copy.deepcopy(RULESET)
        drifted["enforcement"] = "disabled"
        with self.assertRaises(FleetContractError):
            verify_ruleset(PLAN, drifted, "blogle/anvil")

    def test_permission_failure_is_fail_closed(self):
        with self.assertRaises(FleetContractError):
            verify_check_runs(PLAN, {"check_runs": "denied"})

    def test_publisher_mismatch_is_fail_closed(self):
        wrong = copy.deepcopy(CHECK_RUNS)
        wrong["check_runs"][2]["app"]["id"] = 99999
        with self.assertRaises(FleetContractError):
            verify_check_runs(PLAN, wrong)

    def test_redacted_bypass_is_fail_closed(self):
        redacted = copy.deepcopy(RULESET)
        redacted.pop("bypass_actors")
        with self.assertRaises(FleetContractError):
            verify_ruleset(PLAN, redacted, "blogle/anvil")

    def test_nonempty_bypass_is_fail_closed(self):
        bypassed = copy.deepcopy(RULESET)
        bypassed["bypass_actors"] = [{"actor_id": 1}]
        with self.assertRaises(FleetContractError):
            verify_ruleset(PLAN, bypassed, "blogle/anvil")

    def test_missing_secret_is_repaired(self):
        actions = secret_actions(["SDLC_RELEASE_APP_ID"], "1", "1")
        self.assertFalse(actions["SDLC_RELEASE_APP_ID"])
        self.assertTrue(actions["SDLC_RELEASE_APP_PRIVATE_KEY"])

    def test_rekey_reinstalls_both_secrets(self):
        actions = secret_actions(["SDLC_RELEASE_APP_ID", "SDLC_RELEASE_APP_PRIVATE_KEY"], "1", "2")
        self.assertTrue(actions["SDLC_RELEASE_APP_ID"])
        self.assertTrue(actions["SDLC_RELEASE_APP_PRIVATE_KEY"])
        self.assertTrue(actions["SDLC_RELEASE_CREDENTIAL_VERSION"])

    def test_transition_requires_approved_consumer_pin(self):
        verify_consumer_pin(LOCK, FLAKE, "de40fc00bc632b7acd0b0ba5de1242f1af827a9f")
        with self.assertRaises(FleetContractError):
            verify_consumer_pin(LOCK, FLAKE, "0000000000000000000000000000000000000000")


if __name__ == "__main__":
    unittest.main()
