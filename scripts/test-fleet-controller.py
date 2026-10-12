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

    def test_reconcile_is_noop_without_protected_context(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(controller.protected_context())


if __name__ == "__main__":
    unittest.main()
