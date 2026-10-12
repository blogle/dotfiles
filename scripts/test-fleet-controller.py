import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE = Path(__file__).with_name("fleet-controller.py")
SPEC = importlib.util.spec_from_file_location("fleet_controller", MODULE)
controller = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(controller)


class FleetControllerTests(unittest.TestCase):
    def test_manifest_uses_verified_immutable_ids(self):
        manifest = controller.load_manifest()
        self.assertEqual(manifest["owner"]["id"], 4959802)
        self.assertEqual({repo["id"] for repo in manifest["repositories"]},
                         {1402311485, 332889752, 1372267957})

    def test_live_identity_rejects_repository_replacement(self):
        manifest = controller.load_manifest()

        class FakeAPI:
            def get(self, path):
                if path == "users/blogle":
                    return {"login": "blogle", "id": 4959802}
                name = path.rsplit("/", 1)[-1]
                return {"name": name, "id": 1, "owner": {"id": 4959802}}

        with self.assertRaises(ValueError):
            controller.verify_live_identities(manifest, FakeAPI())

    def test_live_identity_accepts_exact_owner_and_repository_ids(self):
        manifest = controller.load_manifest()
        values = {repo["name"]: repo["id"] for repo in manifest["repositories"]}

        class FakeAPI:
            def get(self, path):
                if path == "users/blogle":
                    return {"login": "blogle", "id": 4959802}
                name = path.rsplit("/", 1)[-1]
                return {"name": name, "id": values[name], "owner": {"id": 4959802}}

        self.assertTrue(controller.verify_live_identities(manifest, FakeAPI()))

    def test_security_floor_requires_operator_bypass_before_worker(self):
        floor = controller.load_security_floor()
        self.assertIsNone(floor["human_bypass_actor_id"])
        result = controller.sdlc_adapter(
            "reconcile", controller.MANIFEST, controller.POLICY,
            controller.POLICY, controller.load_controller()["revision"], floor
        )
        self.assertEqual(result["state"], "unknown")

    def test_worker_contract_has_manifest_policy_and_no_legacy_apply_flag(self):
        floor = dict(controller.load_security_floor())
        floor["human_bypass_actor_id"] = 4959802
        completed = type("Completed", (), {"returncode": 0})()
        with patch.dict(os.environ, {"SDLC_CLI": "/trusted/sdlc"}), patch.object(
            Path, "is_file", return_value=True
        ), patch("subprocess.run", return_value=completed) as run:
            result = controller.sdlc_adapter(
                "reconcile", controller.MANIFEST, controller.POLICY,
                controller.POLICY, controller.load_controller()["revision"], floor
            )
        self.assertEqual(result["state"], "prepared")
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["/trusted/sdlc", "fleet", "reconcile"])
        self.assertIn("--manifest", command)
        self.assertIn("--policy", command)
        self.assertIn("--attestation", command)
        self.assertIn("--consumer-pin", command)
        self.assertIn("--trusted-bypass-user-id", command)
        self.assertNotIn("--apply", command)

    def test_controller_pin_is_not_ready_while_sdlc_pr_is_open(self):
        class FakeAPI:
            def get(self, path):
                if path == "repos/blogle/sdlc":
                    return {"id": 1402311485, "default_branch": "main"}
                if "/commits/" in path:
                    return {"sha": controller.load_controller()["revision"]}
                return {
                    "base": {"ref": "main"},
                    "head": {"sha": controller.load_controller()["revision"]},
                    "merged_at": None,
                }

        with self.assertRaisesRegex(ValueError, "not merged"):
            controller.verify_controller_pin(FakeAPI())

    def test_repo_states_are_isolated_and_idempotent(self):
        manifest = controller.load_manifest()
        calls = []

        def worker(repository):
            calls.append(repository["name"])
            return {"state": "unsafe"} if repository["name"] == "anvil" else {"state": "success"}

        results = [controller.reconcile_repository(repo, worker) for repo in manifest["repositories"]]
        self.assertEqual(results[0]["state"], "suspended")
        self.assertEqual(results[1]["state"], "suspended")
        self.assertEqual(results[2]["state"], "unsafe")
        self.assertEqual(calls, ["anvil"])
        self.assertEqual(results, [controller.reconcile_repository(repo, worker) for repo in manifest["repositories"]])

    def test_prepare_release_distribution_reads_metadata_without_writes(self):
        repository = controller.load_manifest()["repositories"][-1]

        class FakeAPI:
            def get(self, path):
                self.path = path
                return {"secrets": [{"name": "OLD"}]}

        api = FakeAPI()
        result = controller.prepare_release_app_distribution(repository, api)
        self.assertFalse(result["write"])
        self.assertEqual(result["existing_names"], ["OLD"])
        self.assertEqual(result["required_names"], ["SDLC_RELEASE_APP_ID", "SDLC_RELEASE_APP_PRIVATE_KEY"])

    def test_reconcile_is_noop_without_protected_context(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(controller.protected_context())


if __name__ == "__main__":
    unittest.main()
