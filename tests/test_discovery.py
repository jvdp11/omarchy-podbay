import ast
import pathlib
import types
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "bin/podbay-daemon"
tree = ast.parse(SOURCE.read_text())


class DBusException(Exception):
    pass


ns = {"dbus": types.SimpleNamespace(DBusException=DBusException), "log": lambda *a: None}
consts = [n for n in tree.body if isinstance(n, ast.Assign)
          and any(isinstance(t, ast.Name) and t.id == "STOP_CHECK_EVERY" for t in n.targets)]
exec(compile(ast.Module(body=consts, type_ignores=[]), str(SOURCE), "exec"), ns)


def method(name):
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Daemon")
    fn = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == name)
    exec(compile(ast.Module(body=[fn], type_ignores=[]), str(SOURCE), "exec"), ns)
    return ns[name]


class FakeBlueZ:
    """One client's view of BlueZ discovery: a session per client, with the
    adapter's shared Discovering flag reported separately (and possibly late)."""

    def __init__(self):
        self.ours = False
        self.calls = []

    def SetDiscoveryFilter(self, f):
        self.calls.append(("filter", f["Transport"]))

    def StartDiscovery(self):
        self.calls.append("start")
        if self.ours:
            raise DBusException("org.bluez.Error.InProgress: Operation already in progress")
        self.ours = True

    def StopDiscovery(self):
        self.calls.append("stop")
        if not self.ours:
            raise DBusException("org.bluez.Error.Failed: No discovery started")
        self.ours = False


def daemon(bluez):
    d = types.SimpleNamespace(adapter_path="/org/bluez/hci0", adapter={"Powered": True, "Discovering": False},
                              discovering_by_us=False, next_stop_check=0, _adapter=lambda: bluez)
    d._stop_discovery = lambda ad: method("_stop_discovery")(d, ad)
    d.sync = lambda want, now=0: method("_sync_discovery")(d, want, now)
    d.props = lambda changed: method("_props_changed")(d, "org.bluez.Adapter1", changed, [], d.adapter_path)
    d.emit = lambda: None
    return d


ns["ADAPTER"] = "org.bluez.Adapter1"


class DiscoveryTests(unittest.TestCase):
    def test_late_discovering_false_after_filter_switch_does_not_orphan_scan(self):
        # The bug: le -> auto restarts the scan; the Stop's Discovering=False
        # arrives after the new Start and used to wipe our ownership, so the
        # scan was never stopped again.
        bz = FakeBlueZ()
        d = daemon(bz)
        d.sync("le")
        d.sync("auto")
        self.assertTrue(bz.ours)
        d.props({"Discovering": False})   # late signal from the restart
        d.adapter["Discovering"] = True
        d.sync("auto")
        d.sync(None)
        self.assertFalse(bz.ours, "scan must end once nothing wants it")

    def test_lost_session_is_adopted_on_in_progress(self):
        bz = FakeBlueZ()
        bz.ours = True                     # running, but we lost track
        d = daemon(bz)
        d.sync("le")
        self.assertEqual(d.discovering_by_us, "le")
        d.sync(None)
        self.assertFalse(bz.ours)

    def test_safety_net_stops_stray_scan_and_is_rate_limited(self):
        bz = FakeBlueZ()
        bz.ours = True
        d = daemon(bz)
        d.adapter["Discovering"] = True
        d.sync(None, now=100)
        self.assertFalse(bz.ours)
        bz.calls.clear()
        d.sync(None, now=101)              # another app's scan: don't hammer
        self.assertEqual(bz.calls, [])
        d.sync(None, now=100 + ns["STOP_CHECK_EVERY"])
        self.assertEqual(bz.calls, ["stop"])

    def test_power_off_clears_ownership(self):
        bz = FakeBlueZ()
        d = daemon(bz)
        d.sync("le")
        d.props({"Powered": False})
        self.assertFalse(d.discovering_by_us)


if __name__ == "__main__":
    unittest.main()
