import importlib.util
import unittest
from pathlib import Path


MODULE = Path(__file__).with_name("fleet-controller.py")
SPEC = importlib.util.spec_from_file_location("fleet_controller", MODULE)
controller = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(controller)


class FleetInventoryTests(unittest.TestCase):
    def test_owner_and_ids_are_pinned(self):
        manifest = controller.load_manifest()
        self.assertEqual(manifest["owner"], {"login": "blogle", "id": 4959802})
        self.assertEqual(
            {repo["name"]: repo["id"] for repo in manifest["repositories"]},
            {"sdlc": 1402311485, "dotfiles": 332889752, "anvil": 1372267957},
        )

    def test_only_anvil_is_enabled(self):
        self.assertEqual([repo["name"] for repo in controller.enabled_repositories(controller.load_manifest())], ["anvil"])


if __name__ == "__main__":
    unittest.main()
