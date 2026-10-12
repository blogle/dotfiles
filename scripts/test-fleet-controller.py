import importlib.util
import base64
import json
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
                return {"name": name, "id": values[name], "owner": {"id": 4959802}, "default_branch": "main"}

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
        consumer_revision = "1" * 40
        with patch.dict(os.environ, {"SDLC_CLI": "/trusted/sdlc"}), patch.object(
            Path, "is_file", return_value=True
        ), patch("subprocess.run", return_value=completed) as run:
            result = controller.sdlc_adapter(
                "reconcile", controller.MANIFEST, controller.POLICY,
                controller.POLICY, consumer_revision, floor
            )
        self.assertEqual(result["state"], "prepared")
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["/trusted/sdlc", "fleet", "reconcile"])
        self.assertIn("--manifest", command)
        self.assertIn("--policy", command)
        self.assertIn("--attestation", command)
        self.assertIn("--consumer-pin", command)
        self.assertEqual(command[command.index("--consumer-pin") + 1], consumer_revision)
        self.assertIn("--trusted-bypass-user-id", command)
        self.assertNotIn("--apply", command)

    def test_controller_pin_is_not_ready_while_sdlc_pr_is_open(self):
        class FakeAPI:
            def get(self, path):
                if path == "repos/blogle/sdlc":
                    return {"id": 1402311485, "default_branch": "main"}
                if "/commits/" in path:
                    return {"sha": controller.load_controller()["revision"]}
                return {"status": "diverged", "behind_by": 0}

        with self.assertRaisesRegex(ValueError, "ancestor"):
            controller.verify_controller_pin(FakeAPI())

    def test_controller_pin_rejects_squash_head_even_if_pr_says_merged(self):
        class FakeAPI:
            def get(self, path):
                if path == "repos/blogle/sdlc":
                    return {"id": 1402311485, "default_branch": "main"}
                if "/commits/" in path:
                    return {"sha": controller.load_controller()["revision"]}
                return {"status": "diverged", "behind_by": 0}

        with self.assertRaisesRegex(ValueError, "ancestor"):
            controller.verify_controller_pin(FakeAPI())

    def test_controller_pin_rejects_moved_main_and_divergence(self):
        class FakeAPI:
            def __init__(self, status, behind_by):
                self.status = status
                self.behind_by = behind_by

            def get(self, path):
                if path == "repos/blogle/sdlc":
                    return {"id": 1402311485, "default_branch": "main"}
                if "/commits/" in path:
                    return {"sha": controller.load_controller()["revision"]}
                return {"status": self.status, "behind_by": self.behind_by}

        for status, behind_by in (("behind", 1), ("diverged", 2)):
            with self.subTest(status=status):
                with self.assertRaisesRegex(ValueError, "repin"):
                    controller.verify_controller_pin(FakeAPI(status, behind_by))

    def test_controller_pin_accepts_only_compare_proven_ancestor(self):
        class FakeAPI:
            def get(self, path):
                if path == "repos/blogle/sdlc":
                    return {"id": 1402311485, "default_branch": "main"}
                if "/commits/" in path:
                    return {"sha": controller.load_controller()["revision"]}
                return {"status": "ahead", "behind_by": 0}

        self.assertTrue(controller.verify_controller_pin(FakeAPI())["reachable_from_protected"])

    def test_consumers_resolve_independent_pins_and_rollback(self):
        pins = {"anvil": "1" * 40, "dotfiles": "2" * 40}
        refs = {"anvil": "v1.2.0", "dotfiles": "v1.1.1"}

        class FakeAPI:
            def get(self, path):
                name = path.split("/")[2] if "/contents/" in path else None
                if name in pins:
                    lock = {"nodes": {"root": {"inputs": {"sdlc": "sdlc"}}, "sdlc": {
                        "locked": {"type": "github", "owner": "blogle", "repo": "sdlc", "rev": pins[name]},
                        "original": {"type": "github", "owner": "blogle", "repo": "sdlc", "ref": refs[name]},
                    }}}
                    return {"encoding": "base64", "content": base64.b64encode(json.dumps(lock).encode()).decode()}
                if "/commits/" in path:
                    return {"sha": path.rsplit("/", 1)[-1]}
                if "/compare/" in path:
                    return {"status": "ahead", "behind_by": 0}
                raise AssertionError(path)

        anvil = controller.resolve_consumer_pin({"name": "anvil"}, {"default_branch": "main"}, FakeAPI())
        dotfiles = controller.resolve_consumer_pin({"name": "dotfiles"}, {"default_branch": "main"}, FakeAPI())
        self.assertNotEqual(anvil["revision"], dotfiles["revision"])
        self.assertEqual(dotfiles["ref"], "v1.1.1")

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
        result = controller.prepare_release_app_distribution_for_contract(repository, api, {
            "environment": "sdlc-release",
            "observed_permissions": {"environments": "write"},
            "observed_workflow": {
                "called_job_environment": "sdlc-release",
                "reads_environment_secrets": True,
            },
        })
        self.assertFalse(result["write"])
        self.assertEqual(result["existing_names"], ["OLD"])
        self.assertEqual(result["required_names"], ["SDLC_RELEASE_APP_ID", "SDLC_RELEASE_APP_PRIVATE_KEY"])
        self.assertIn("environments/sdlc-release/secrets", api.path)

    def test_release_distribution_blocks_missing_environment_permission_without_fallback(self):
        repository = controller.load_manifest()["repositories"][-1]

        class FakeAPI:
            def get(self, path):
                raise AssertionError("must not read or write a repository-secret endpoint")

        result = controller.prepare_release_app_distribution_for_contract(repository, FakeAPI(), {
            "environment": "sdlc-release",
            "observed_permissions": {"actions_secrets": "write", "secrets": "write"},
            "observed_workflow": {},
        })
        self.assertEqual(result["state"], "unknown")
        self.assertFalse(result["repository_secret_fallback"])

    def test_release_distribution_blocks_missing_environment_wiring(self):
        repository = controller.load_manifest()["repositories"][-1]

        class FakeAPI:
            def get(self, path):
                raise AssertionError("must not read secrets without workflow wiring")

        result = controller.prepare_release_app_distribution_for_contract(repository, FakeAPI(), {
            "environment": "sdlc-release",
            "observed_permissions": {"environments": "write"},
            "observed_workflow": {"reads_environment_secrets": False},
        })
        self.assertEqual(result["state"], "unsafe")
        self.assertFalse(result["repository_secret_fallback"])

    def test_reconcile_is_noop_without_protected_context(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(controller.protected_context())


if __name__ == "__main__":
    unittest.main()
