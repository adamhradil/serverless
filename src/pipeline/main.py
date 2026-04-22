import os
import logging
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
    logging.info("Azure Monitor enabled.")


def main():
    logging.info("Starting ETL run...")

    result = run_pipeline()
    if result["status"] == "error":
        logging.error("ETL failed: %s", result["message"])
    else:
        logging.info("ETL complete: %s", result["message"])


if __name__ == "__main__":
    main()
