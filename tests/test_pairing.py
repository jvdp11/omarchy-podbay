import ast
import pathlib
import time
import types
import unittest
from unittest.mock import Mock

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "bin/podbay-daemon"
tree = ast.parse(SOURCE.read_text())
ns = {"time": time, "dbus": types.SimpleNamespace(DBusException=RuntimeError)}
functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ("is_airpods", "pid_from_modalias")]
constants = [n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(x, ast.Name) and x.id == "AUDIO_SERVICES" for x in n.targets)]
exec(compile(ast.Module(body=constants + functions, type_ignores=[]), str(SOURCE), "exec"), ns)

def method(class_name, name):
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == class_name)
    fn = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == name)
    fn.decorator_list = []
    exec(compile(ast.Module(body=[fn], type_ignores=[]), str(SOURCE), "exec"), ns)
    return ns[name]

class PairingTests(unittest.TestCase):
    def test_legacy_auto_pair_cannot_pair_on_panel_or_advert(self):
        device = {"Name": "Attacker AirPods", "Class": 1024, "AddressType": "public"}
        self.assertTrue(ns["is_airpods"](device))
        for watch, until in ((True, 0), (False, time.time() + 60)):
            fake = types.SimpleNamespace(devices={"fake": device}, settings={"autoPair": True}, pairing=set(), watch=watch, pair_until=until, pair=Mock())
            method("Daemon", "_maybe_autopair")(fake, "fake")
            fake.pair.assert_not_called()

    def test_service_rejects_hid_even_for_chosen_pair(self):
        fake = types.SimpleNamespace(_check=Mock())
        auth = method("Agent", "AuthorizeService")
        with self.assertRaises(RuntimeError):
            auth(fake, "chosen", "00001124-0000-1000-8000-00805f9b34fb")
        auth(fake, "chosen", "0000110b-0000-1000-8000-00805f9b34fb")

    def test_only_trusted_pairs_auto_connect(self):
        fake = types.SimpleNamespace(devices={
            "trusted": {"Paired": True, "Trusted": True, "Modalias": "bluetooth:v004Cp2014d0A01"},
            "untrusted": {"Paired": True, "Trusted": False, "Modalias": "bluetooth:v004Cp2014d0A01"}})
        self.assertEqual(method("Daemon", "_paired_of_model")(fake, 0x2014), ["trusted"])

    def test_manual_connect_does_not_require_trusted_flag(self):
        fake = types.SimpleNamespace(error="", manual_off=set(), devices={}, _dev=Mock(), _fail=Mock())
        method("Daemon", "connect")(fake, "user-chosen")
        fake._dev.assert_called_once_with("user-chosen")
        fake._dev.return_value.Connect.assert_called_once()
