import copy
import json
import pathlib
import unittest

from scripts.sdlc_fleet import (
    FleetContractError,
    attest_rulesets,
    secret_actions,
    select_candidate_pr,
    verify_check_runs,
    verify_check_runs_for_head,
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
    def test_renovate_labels_unattended_managers_auto_and_other_updates_review(self):
        config = (pathlib.Path(__file__).parents[1] / "renovate.json5").read_text()
        self.assertIn("labels: ['dependencies', 'kubernetes', 'integration:review']", config)
        self.assertIn("labels: ['dependencies', 'kubernetes', 'integration:auto']", config)

    def test_two_layer_attestation_normalizes_timezones_and_rejects_extra_actors(self):
        plan = copy.deepcopy(PLAN)
        desired = {
            "name": "SDLC automated merges", "target": "branch", "enforcement": "active",
            "conditions": RULESET["conditions"], "rules": [{"type": "update"}],
            "bypass_actors": [
                {"actor_id": 10562, "actor_type": "Integration", "bypass_mode": "pull_request"},
                {"actor_id": 5257759, "actor_type": "Integration", "bypass_mode": "pull_request"},
            ],
        }
        plan["automated_merges"] = desired
        actual = dict(copy.deepcopy(desired), id=43, updated_at="2026-10-15T00:00:00-07:00")
        result = attest_rulesets(plan, RULESET, actual, "blogle/anvil")
        self.assertEqual(result["updated_at"], "2026-10-15T07:00:00.000Z")
        self.assertEqual(result["automated_merges"]["updated_at"], result["updated_at"])
        self.assertEqual(result["automated_merges"]["bypass_actors"], desired["bypass_actors"])
        actual["bypass_actors"].append({"actor_id": 1, "actor_type": "Team", "bypass_mode": "always"})
        with self.assertRaises(FleetContractError):
            attest_rulesets(plan, RULESET, actual, "blogle/anvil")

    def test_first_apply_plan_has_real_required_checks(self):
        self.assertEqual(PLAN["action"], "create")
        verify_check_runs(PLAN, CHECK_RUNS)

    def test_latest_matching_pr_head_is_selected_across_pages(self):
        pages = [[
            {"base": {"ref": "main"}, "head": {"sha": "old"}, "updated_at": "2026-01-01T00:00:00Z"},
        ], [
            {"base": {"ref": "main"}, "head": {"sha": "new"}, "updated_at": "2026-01-02T00:00:00Z"},
            {"base": {"ref": "other"}, "head": {"sha": "wrong"}, "updated_at": "2026-01-03T00:00:00Z"},
        ]]
        self.assertEqual(select_candidate_pr(pages, "main")["head"]["sha"], "new")

    def test_check_runs_must_match_selected_head(self):
        with self.assertRaises(FleetContractError):
            verify_check_runs_for_head(PLAN, CHECK_RUNS, "current-head")

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

    def test_transition_rejects_comment_only_package_claim(self):
        with self.assertRaises(FleetContractError):
            verify_consumer_pin(LOCK, "# packages.sdlc = sdlc.packages.${system}.sdlc;", "de40fc00bc632b7acd0b0ba5de1242f1af827a9f")


if __name__ == "__main__":
    unittest.main()
