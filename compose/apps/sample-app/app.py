import os
import socket

from flask import Flask, jsonify


app = Flask(__name__)


@app.get("/")
def index():
    hostname = socket.gethostname()
    return (
        "<!doctype html>"
        "<html lang=\"en\">"
        "<head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        "<title>Campsites</title>"
        "<style>"
        "body{font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#f5f7fa;color:#17202a;}"
        "main{max-width:42rem;padding:2rem;}"
        "h1{font-size:clamp(2rem,7vw,4rem);margin:0 0 1rem;letter-spacing:0;}"
        "p{font-size:1.125rem;line-height:1.5;margin:0.5rem 0;}"
        "code{background:#e8edf3;border-radius:4px;padding:0.15rem 0.35rem;}"
        "</style></head>"
        "<body><main>"
        "<h1>Hello from Campsites</h1>"
        "<p>This Flask app is being served through Caddy on the home server.</p>"
        f"<p>Container hostname: <code>{hostname}</code></p>"
        "</main></body></html>"
    )


@app.get("/healthz")
def healthz():
    return jsonify(status="ok", service="campsites-sample")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8000"))
    app.run(host="0.0.0.0", port=port)
