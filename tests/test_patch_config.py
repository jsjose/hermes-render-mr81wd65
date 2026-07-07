from __future__ import annotations

import importlib.util
import sys
import types
import unittest
from pathlib import Path


def load_patch_config():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "patch-config.py"
    spec = importlib.util.spec_from_file_location("patch_config", module_path)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules.setdefault("yaml", types.SimpleNamespace())
    spec.loader.exec_module(module)
    return module


class PatchConfigTests(unittest.TestCase):
    def test_default_render_mcp_entry_does_not_filter_tools(self):
        patch_config = load_patch_config()

        render_entry = patch_config._render_entry()

        self.assertNotIn("tools", render_entry)

    def test_ensure_dashboard_basic_auth_inserts_when_missing_and_creds_provided(self):
        patch_config = load_patch_config()
        config: dict = {}

        changed = patch_config.ensure_dashboard_basic_auth(config, "admin", "hashed-value")

        self.assertTrue(changed)
        self.assertEqual(
            config["dashboard"]["basic_auth"],
            {"username": "admin", "password_hash": "hashed-value"},
        )

    def test_ensure_dashboard_basic_auth_noop_when_creds_missing(self):
        patch_config = load_patch_config()
        config: dict = {}

        changed = patch_config.ensure_dashboard_basic_auth(config, None, None)

        self.assertFalse(changed)
        self.assertNotIn("dashboard", config)

    def test_ensure_dashboard_basic_auth_does_not_overwrite_existing(self):
        patch_config = load_patch_config()
        config = {"dashboard": {"basic_auth": {"username": "keep-me", "password_hash": "keep-hash"}}}

        changed = patch_config.ensure_dashboard_basic_auth(config, "admin", "hashed-value")

        self.assertFalse(changed)
        self.assertEqual(config["dashboard"]["basic_auth"]["username"], "keep-me")
