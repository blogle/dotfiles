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
        self.assertFalse(floor.get("human_bypass_actor_id"))

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

    def test_anvil_fake_apply_reaches_ready_and_is_idempotent(self):
        manifest = controller.load_manifest()
        manifest["repositories"] = [dict(repo) for repo in manifest["repositories"] if repo["name"] == "anvil"]
        pin = "3" * 40

        class FakeAPI:
            def __init__(self):
                self.ruleset = False
                self.secrets = set()
                self.variables = {}
                self.writes = []

            def get(self, path):
                if path == "users/blogle":
                    return {"login": "blogle", "id": 4959802}
                if path == "repos/blogle/anvil":
                    return {"id": 1372267957, "name": "anvil", "owner": {"id": 4959802}, "default_branch": "master"}
                if path == "repos/blogle/anvil/installation":
                    return {"installation_verified": True, "permissions": {"administration": "write", "actions_secrets": "write", "actions_variables": "write", "environments": "write"}}
                if "contents/flake.lock" in path:
                    lock = {"nodes": {"root": {"inputs": {"sdlc": "sdlc"}}, "sdlc": {"locked": {"type": "github", "owner": "blogle", "repo": "sdlc", "rev": pin}, "original": {"ref": "v1.2.0"}}}}
                    return {"encoding": "base64", "content": base64.b64encode(json.dumps(lock).encode()).decode()}
                if "/commits/" in path:
                    return {"sha": pin}
                if "/compare/" in path:
                    return {"status": "ahead", "behind_by": 0}
                if "contents/.github/workflows/sdlc.yml" in path:
                    caller = "sdlc-check sdlc-verify sdlc-policy " + pin
                    return {"encoding": "base64", "content": base64.b64encode(caller.encode()).decode()}
                if "contents/.github/workflows/release.yml" in path:
                    release = "environment: sdlc-release\nsecrets: inherit\n"
                    return {"encoding": "base64", "content": base64.b64encode(release.encode()).decode()}
                if "/environments/sdlc-release" in path and path.endswith("/secrets"):
                    return {"secrets": [{"name": name} for name in sorted(self.secrets)]}
                if "/environments/sdlc-release" in path and path.endswith("/variables/SDLC_RELEASE_ACTIVATE"):
                    return {"name": "SDLC_RELEASE_ACTIVATE", "value": self.variables.get("SDLC_RELEASE_ACTIVATE")}
                if path.endswith("/environments/sdlc-release"):
                    return {"deployment_branch_policy": {"protected_branches": True, "custom_branch_policies": False}}
                raise AssertionError(path)

            def put_environment_secret(self, repository, environment, name, value):
                if name in self.secrets:
                    return False
                self.secrets.add(name)
                self.writes.append(f"secret:{name}")
                return True

            def put_environment_variable(self, repository, environment, name, value):
                if self.variables.get(name) == value:
                    return False
                self.variables[name] = value
                self.writes.append(f"variable:{name}")
                return True

            def verify_environment_secrets(self, repository, environment, names):
                return self.secrets == set(names)

            def verify_environment_variable(self, repository, environment, name, value):
                return self.variables.get(name) == value

        class FakeWorker:
            def __init__(self):
                self.policy_ready = False

            def verify_callers(self, workflow, consumer_pin):
                return {"state": "ready"}

            def apply_and_verify_policy(self, repository, branch, consumer_pin):
                self.policy_ready = True
                return {"state": "ready"}

        api = FakeAPI()
        worker = FakeWorker()
        with patch.dict(os.environ, {"SDLC_RELEASE_APP_ID": "id", "SDLC_RELEASE_APP_PRIVATE_KEY": "key"}):
            self.assertEqual(controller.reconcile_anvil(manifest, api, worker)["state"], "unknown")
            first = controller.reconcile_anvil(manifest, api, worker, apply=True)
            second = controller.reconcile_anvil(manifest, api, worker, apply=True)
        self.assertTrue(first["ready"])
        self.assertTrue(second["ready"])
        self.assertEqual(len(api.writes), 3)

    def test_anvil_fake_apply_unknown_unsafe_and_suspended(self):
        manifest = controller.load_manifest()
        manifest["repositories"] = [dict(repo) for repo in manifest["repositories"] if repo["name"] == "anvil"]

        class MissingInstallation:
            def get(self, path):
                if path == "users/blogle":
                    return {"login": "blogle", "id": 4959802}
                if path == "repos/blogle/anvil":
                    return {"id": 1372267957, "name": "anvil", "owner": {"id": 4959802}, "default_branch": "master"}
                raise ValueError("installation unavailable")

        class UnsafeWorker:
            def verify_callers(self, workflow, consumer_pin):
                return {"state": "unsafe"}

        self.assertEqual(controller.reconcile_anvil(manifest, MissingInstallation(), UnsafeWorker())["state"], "unknown")
        manifest["repositories"][0]["state"] = "suspended"
        self.assertEqual(controller.reconcile_anvil(manifest, MissingInstallation(), UnsafeWorker())["state"], "suspended")


if __name__ == "__main__":
    unittest.main()
