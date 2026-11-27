import ast
import pathlib
import time
import types
import unittest
from unittest.mock import Mock

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "bin/podbay-daemon"
tree = ast.parse(SOURCE.read_text())
ns = {"time": time, "dbus": types.SimpleNamespace(DBusException=RuntimeError)}
functions = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ("is_airpods", "pid_from_modalias", "split_lines")]
constants = [n for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(x, ast.Name) and x.id in ("AUDIO_SERVICES", "STDIN_MAX", "PAIRING_MODE_TTL", "PAIRING_MODE_MAX", "PAIRING_EVENT_GAP", "AAP_RETRIES") for x in n.targets)]
exec(compile(ast.Module(body=constants + functions, type_ignores=[]), str(SOURCE), "exec"), ns)

def method(class_name, name):
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == class_name)
    fn = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == name)
    fn.decorator_list = []
    exec(compile(ast.Module(body=[fn], type_ignores=[]), str(SOURCE), "exec"), ns)
    return ns[name]

class PairingTests(unittest.TestCase):
    def test_stdin_lines(self):
        split = ns["split_lines"]
        self.assertEqual(split(b"", b'{"a":1}\n{"b":2}\n'), ([b'{"a":1}', b'{"b":2}'], b""))
        lines, rest = split(b"", b'{"a":1}\n{"b"')
        self.assertEqual((lines, rest), ([b'{"a":1}'], b'{"b"'))
        self.assertEqual(split(rest, b':2}\n'), ([b'{"b":2}'], b""))
        self.assertEqual(split(b"", b"x" * (ns["STDIN_MAX"] + 1)), ([], b""))

    def test_pairing_mode_is_bounded_and_rate_limited(self):
        fake = types.SimpleNamespace(pairing_mode={}, pairing_event_at={})
        note = lambda a, now: method("Daemon", "_note_pairing_mode")(fake, a, 0x2014, now)
        self.assertTrue(note("AA", 100))
        self.assertFalse(note("AA", 110), "same address while it is still in pairing mode")
        self.assertFalse(note("AA", 150), "entry expired but the event was sent a moment ago")
        self.assertTrue(note("AA", 200))
        for i in range(100):
            note("B%d" % i, 200)
        self.assertEqual(len(fake.pairing_mode), ns["PAIRING_MODE_MAX"])
        self.assertLessEqual(len(fake.pairing_event_at), ns["PAIRING_MODE_MAX"])
        self.assertIn("B99", fake.pairing_mode)
        note("C", 300)
        self.assertEqual(list(fake.pairing_mode), ["C"], "the rest has expired")

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

    def _appearing(self, **over):
        devices = {"max": {"Paired": True, "Trusted": True, "Address": "70:F9:4A:00:00:01",
                           "Modalias": "bluetooth:v004Cp202Dd0A01"}}
        fake = types.SimpleNamespace(
            devices=devices, settings={"autoConnect": True, "manualOnly": [], "order": []},
            manual_off=set(), offered=set(), event=Mock(), connect=Mock(), _title=lambda path: "AirPods Max 2")
        for name in ("_paired_of_model", "_rank", "_connected_airpods"):
            setattr(fake, name, types.MethodType(method("Daemon", name), fake))
        for k, v in over.items():
            setattr(fake, k, v)
        return fake

    def test_appearing_pair_is_offered_once_and_never_connected(self):
        fake = self._appearing()
        offer = method("Daemon", "_auto_connect")
        offer(fake, 0x202D)
        offer(fake, 0x202D)  # still around, or back before it counted as gone
        fake.connect.assert_not_called()
        fake.event.assert_called_once_with("offer", address="70:F9:4A:00:00:01", title="AirPods Max 2")

    def test_no_offer_when_off_manual_or_disconnected_by_hand(self):
        offer = method("Daemon", "_auto_connect")
        for fake in (self._appearing(settings={"autoConnect": False, "manualOnly": [], "order": []}),
                     self._appearing(settings={"autoConnect": True, "manualOnly": ["70:f9:4a:00:00:01"], "order": []}),
                     self._appearing(manual_off={"max"})):
            offer(fake, 0x202D)
            fake.event.assert_not_called()
            fake.connect.assert_not_called()

    def test_accept_connects_only_what_was_offered(self):
        accept = method("Daemon", "accept")
        fake = self._appearing()
        accept(fake, "max")
        fake.connect.assert_not_called()
        fake.offered.add("max")
        accept(fake, "max")
        fake.connect.assert_called_once_with("max", replace=[])


if __name__ == "__main__":
    unittest.main()
