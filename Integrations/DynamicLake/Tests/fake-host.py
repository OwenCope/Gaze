#!/usr/bin/env python3
"""Stands in for DynamicLake: opens the JSON socket, launches the plugin, prints and checks each frame.

Usage: fake-host.py <plugin-executable> [seconds]
Run simulate-gaze.swift in another terminal while this is listening.
"""
import json, os, socket, struct, subprocess, sys, tempfile, threading, time

TINTS = {"blue", "cyan", "teal", "indigo", "purple", "pink", "green", "orange", "yellow", "red", "gray", "white"}
STATUSES = {"success", "failed", "inProgress", "paused", "warning"}
IDCHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")

def check_component(c, where):
    t = c.get("type")
    assert t in {"text", "image", "button", "progress", "timer", "status"}, f"{where}: bad type {t}"
    if "tint" in c: assert c["tint"] in TINTS, f"{where}: bad tint"
    if t == "text": assert isinstance(c.get("text"), str)
    if t == "image":
        assert c.get("source") in {"sfSymbol", "appIcon", "inlineData"}
        if c["source"] == "sfSymbol": assert c.get("systemImage")
    if t == "status": assert c.get("status") in STATUSES
    if t == "progress" and "value" in c: assert 0 <= c["value"] <= 1

def check(m):
    assert m.get("schemaVersion") == 1, "schemaVersion"
    t = m.get("type")
    assert t in {"create", "update", "dismiss"}, f"type {t}"
    if "title" in m: assert len(m["title"]) <= 80
    if "activityID" in m: assert set(m["activityID"]) <= IDCHARS
    if t in {"create", "update"}: assert m.get("activityID"), "activityID"
    if t == "create":
        assert "compactLiveActivity" in m.get("surfaces", {}), "compactLiveActivity required"
        assert m.get("priority", "normal") in {"low", "normal", "high"}
        assert m.get("size", "normal") in {"small", "normal", "large"}
    if "presentSneakPeek" in m: assert 1 <= m["presentSneakPeek"] <= 10
    for name, slots in m.get("surfaces", {}).items():
        allowed = {"compactLiveActivity": {"leftSlot", "rightSlot"},
                   "sneakPeek": {"leftSlot", "center", "rightSlot"}}[name]
        assert set(slots) <= allowed, f"{name}: bad slot"
        for slot, c in slots.items(): check_component(c, f"{name}.{slot}")

def read_exact(conn, n):
    data = b""
    while len(data) < n:
        chunk = conn.recv(n - len(data))
        if not chunk: return None
        data += chunk
    return data

def main():
    exe, seconds = sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 30
    tmp = tempfile.mkdtemp()
    path = os.path.join(tmp, "dl.sock")
    settings = os.path.join(tmp, "settings.json")
    with open(settings, "w") as f: json.dump({"showMovementPrompts": True, "showAppLock": True}, f)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path); server.listen(1)
    env = dict(os.environ, DYNAMICLAKE_JSON_SOCKET=path, DYNAMICLAKE_PLUGIN_SETTINGS_PATH=settings,
               DYNAMICLAKE_PLUGIN_FEATURES="numericText,presentSneakPeek")
    proc = subprocess.Popen([exe], env=env)
    conn, _ = server.accept()
    print(f"plugin connected, listening {seconds:.0f}s", flush=True)
    bad = 0
    def reader():
        nonlocal bad
        while (head := read_exact(conn, 4)) is not None:
            (n,) = struct.unpack(">I", head)
            assert n <= 64 * 1024, "frame over 64 KB"
            m = json.loads(read_exact(conn, n).decode("utf-8"))
            try:
                check(m); verdict = "ok"
                reply = {"schemaVersion": 1, "type": "response", "activityID": m.get("activityID"), "ok": True}
            except AssertionError as e:
                bad += 1; verdict = f"INVALID: {e}"
                reply = {"schemaVersion": 1, "type": "error", "ok": False, "error": str(e)}
            print(f"[{verdict}] {json.dumps(m, sort_keys=True)}", flush=True)
            body = json.dumps(reply).encode()
            conn.sendall(struct.pack(">I", len(body)) + body)
    threading.Thread(target=reader, daemon=True).start()
    time.sleep(seconds)
    conn.close()  # Closing the socket must make the plugin exit.
    try:
        proc.wait(timeout=3); print(f"plugin exited with {proc.returncode} after socket close")
    except subprocess.TimeoutExpired:
        proc.kill(); print("FAIL: plugin did not exit after socket close"); bad += 1
    print("all frames valid" if bad == 0 else f"{bad} invalid frame(s)")
    sys.exit(1 if bad else 0)

main()
