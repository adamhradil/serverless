import json
import logging
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from azure.monitor.opentelemetry import configure_azure_monitor

from etl import run_pipeline
from log_format import JsonFormatter

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logging.getLogger("azure").setLevel(logging.WARNING)

connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
if connection_string:
    configure_azure_monitor(connection_string=connection_string)
    logging.info("Azure Monitor enabled for FaaS.")


class _CaptureHandler(logging.Handler):
    def __init__(self):
        super().__init__()
        self.records = []

    def emit(self, record):
        self.records.append(json.loads(JsonFormatter().format(record)))


class ETLHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/run":
            api_key = os.environ.get("API_KEY")
            if api_key and self.headers.get("X-Api-Key") != api_key:
                self.send_response(401)
                self.end_headers()
                return

            capture = _CaptureHandler()
            root = logging.getLogger()
            root.addHandler(capture)
            try:
                logging.info("ETL trigger received via HTTP POST /run")
                result = run_pipeline()
            finally:
                root.removeHandler(capture)

            result["logs"] = capture.records
            status = 200 if result["status"] == "success" else 500
            body = json.dumps(result).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        logging.info("HTTP %s", format % args)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    logging.info("Starting ETL HTTP server on port %d", port)
    HTTPServer(("0.0.0.0", port), ETLHandler).serve_forever()
