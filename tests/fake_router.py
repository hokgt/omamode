"""Fake llama.cpp router server for omamode tests.

Implements the subset of the router API omamode uses, plus /_ctl to set
its state from tests.
"""
import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE = {
    "models": [],
    "loaded": None,
    "loading": None,
    "busy": False,
    "load_delay": 0.0,
    "fail_load": False,
    "unload_calls": 0,
    "load_calls": [],
}
LOCK = threading.Lock()
SINGLE = False


def status_of(model_id):
    if STATE["loaded"] == model_id:
        return "loaded"
    if STATE["loading"] == model_id:
        return "loading"
    return "unloaded"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            return json.loads(raw or b"{}")
        except ValueError:
            return {}

    def do_GET(self):
        url = urlparse(self.path)
        with LOCK:
            if url.path == "/health":
                return self.send_json(200, {"status": "ok"})
            if url.path == "/_ctl":
                return self.send_json(200, STATE)
            if url.path == "/models":
                if SINGLE:
                    # A real single-model llama-server lists its one model
                    # without router status.
                    return self.send_json(200, {"object": "list", "data": [{"id": "single", "object": "model"}]})
                data = [
                    {"id": m, "object": "model", "status": {"value": status_of(m)}}
                    for m in STATE["models"]
                ]
                return self.send_json(200, {"object": "list", "data": data})
            if url.path == "/slots":
                model = parse_qs(url.query).get("model", [None])[0]
                if not model:
                    return self.send_json(400, {"error": {"code": 400, "message": "model name is missing from the request"}})
                if status_of(model) != "loaded":
                    return self.send_json(400, {"error": {"code": 400, "message": "model is not loaded"}})
                return self.send_json(200, [{"id": 0, "is_processing": STATE["busy"]}, {"id": 1, "is_processing": False}])
        self.send_json(404, {"error": {"code": 404, "message": "File Not Found"}})

    def do_POST(self):
        url = urlparse(self.path)
        body = self.read_json()
        with LOCK:
            if url.path == "/_ctl":
                STATE.update(body)
                return self.send_json(200, STATE)
            if SINGLE:
                return self.send_json(404, {"error": {"code": 404, "message": "File Not Found"}})
            model = body.get("model")
            if url.path == "/models/load":
                STATE["load_calls"].append(model)
                if model not in STATE["models"]:
                    return self.send_json(400, {"error": {"code": 400, "message": "model not found"}})
                if STATE["fail_load"]:
                    return self.send_json(500, {"error": {"code": 500, "message": "failed to load model"}})
                STATE["loading"] = model
                delay = STATE["load_delay"]
            elif url.path == "/models/unload":
                STATE["unload_calls"] += 1
                if STATE["loaded"] == model:
                    STATE["loaded"] = None
                return self.send_json(200, {"success": True})
            else:
                return self.send_json(404, {"error": {"code": 404, "message": "File Not Found"}})

        def finish():
            time.sleep(delay)
            with LOCK:
                if STATE["loading"] == model:
                    STATE["loaded"] = model
                    STATE["loading"] = None

        threading.Thread(target=finish, daemon=True).start()
        self.send_json(200, {"success": True})


def main():
    global SINGLE
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--single-model", action="store_true")
    args = ap.parse_args()
    SINGLE = args.single_model
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
