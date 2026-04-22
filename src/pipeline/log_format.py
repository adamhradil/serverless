import json
import logging


class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps(
            {
                "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S")
                + f".{int(record.msecs):03d}Z",
                "level": record.levelname,
                "file": record.filename,
                "line": record.lineno,
                "msg": record.getMessage(),
            }
        )
