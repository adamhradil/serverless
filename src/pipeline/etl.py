import os
import re
import logging
import json
import urllib3
import pyodbc
import pandas as pd
from dotenv import load_dotenv
from log_format import JsonFormatter


def extract():
    GOLEMIO_API_KEY = os.environ.get("GOLEMIO_API_KEY")
    logging.info("Extracting data from Golemio API...")
    if not GOLEMIO_API_KEY:
        raise ValueError("GOLEMIO_API_KEY environment variable is not set")

    http = urllib3.PoolManager()
    url = "https://api.golemio.cz/v2/vehiclepositions?limit=10000"
    headers = {"X-Access-Token": GOLEMIO_API_KEY, "Content-Type": "application/json"}

    response = http.request("GET", url, headers=headers, timeout=30.0)
    if response.status != 200:
        raise Exception(
            f"Failed to fetch data: {response.status} {response.data.decode()}"
        )

    return json.loads(response.data.decode())


def transform(data):
    logging.info("Transforming data using pandas...")
    features = data.get("features", [])
    if not features:
        logging.warning("No features found in data")
        return pd.DataFrame()

    df = pd.json_normalize(features)

    column_mapping = {
        "properties.trip.gtfs.trip_id": "trip_id",
        "properties.last_position.origin_timestamp": "origin_timestamp",
        "properties.trip.gtfs.route_short_name": "route_short_name",
        "properties.trip.gtfs.trip_headsign": "trip_headsign",
        "properties.last_position.delay.actual": "delay_actual",
        "properties.last_position.state_position": "state_position",
        "properties.trip.vehicle_registration_number": "vehicle_registration_number",
        "properties.last_position.is_canceled": "is_canceled",
    }

    existing_columns = [col for col in column_mapping.keys() if col in df.columns]
    df_transformed = (
        df[existing_columns]
        .rename(columns={col: column_mapping[col] for col in existing_columns})
        .copy()
    )

    if "geometry.coordinates" in df.columns:
        df_transformed["longitude"] = df["geometry.coordinates"].str[0]
        df_transformed["latitude"] = df["geometry.coordinates"].str[1]
    else:
        df_transformed["longitude"] = None
        df_transformed["latitude"] = None

    if "origin_timestamp" in df_transformed.columns:
        df_transformed["origin_timestamp"] = pd.to_datetime(
            df_transformed["origin_timestamp"]
        )

    for col in ["longitude", "latitude"]:
        if col in df_transformed.columns:
            df_transformed[col] = df_transformed[col].astype(float)

    if "delay_actual" in df_transformed.columns:
        df_transformed["delay_actual"] = df_transformed["delay_actual"].astype("Int64")

    if "vehicle_registration_number" in df_transformed.columns:
        df_transformed["vehicle_registration_number"] = df_transformed[
            "vehicle_registration_number"
        ].astype("Int64")

    if "is_canceled" in df_transformed.columns:
        df_transformed["is_canceled"] = (
            df_transformed["is_canceled"].fillna(False).astype(bool)
        )
    else:
        df_transformed["is_canceled"] = False

    final_columns = [
        "trip_id",
        "origin_timestamp",
        "route_short_name",
        "trip_headsign",
        "latitude",
        "longitude",
        "delay_actual",
        "state_position",
        "vehicle_registration_number",
        "is_canceled",
    ]
    for col in final_columns:
        if col not in df_transformed.columns:
            df_transformed[col] = None

    return df_transformed[final_columns]


def load(df):
    SQL_SERVER = os.environ.get("SQL_SERVER")
    SQL_DATABASE = os.environ.get("SQL_DATABASE", "etl-db")
    SQL_USER = os.environ.get("SQL_USER")
    SQL_PASSWORD = os.environ.get("SQL_PASSWORD")
    TABLE_NAME = os.environ.get("TABLE_NAME", "VehiclePositions")

    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", TABLE_NAME):
        raise ValueError(f"Invalid TABLE_NAME: {TABLE_NAME!r}")

    if df.empty:
        logging.info("No data to load.")
        return {"status": "success", "message": "No data to load"}

    logging.info("Loading %d rows into SQL...", len(df))
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server=tcp:{SQL_SERVER},1433;"
        f"Database={SQL_DATABASE};"
        f"Uid={SQL_USER};"
        f"Pwd={SQL_PASSWORD};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )

    try:
        with pyodbc.connect(conn_str) as conn:
            with conn.cursor() as cursor:
                df_clean = df.dropna(subset=["trip_id", "origin_timestamp"])
                if len(df_clean) < len(df):
                    logging.warning(
                        "Dropped %d rows with null trip_id or origin_timestamp",
                        len(df) - len(df_clean),
                    )

                cursor.execute(f"""
                    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '{TABLE_NAME}')
                    CREATE TABLE {TABLE_NAME} (
                        trip_id NVARCHAR(100) NOT NULL,
                        origin_timestamp DATETIMEOFFSET NOT NULL,
                        route_short_name NVARCHAR(50),
                        trip_headsign NVARCHAR(255),
                        latitude FLOAT,
                        longitude FLOAT,
                        delay_actual INT,
                        state_position NVARCHAR(50),
                        vehicle_registration_number INT,
                        is_canceled BIT,
                        inserted_at DATETIME DEFAULT GETDATE(),
                        CONSTRAINT PK_{TABLE_NAME} PRIMARY KEY (trip_id, origin_timestamp)
                    )
                """)

                insert_sql = f"""
                    INSERT INTO {TABLE_NAME} (
                        trip_id, origin_timestamp, route_short_name, trip_headsign,
                        latitude, longitude, delay_actual, state_position,
                        vehicle_registration_number, is_canceled
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """

                records = []
                for _, row in df_clean.iterrows():
                    # Ensure timestamp is either None or a datetime object (not isoformat string)
                    ts = row["origin_timestamp"]
                    if pd.notnull(ts) and hasattr(ts, "to_pydatetime"):
                        ts = ts.to_pydatetime()
                    elif pd.isnull(ts):
                        ts = None

                    records.append(
                        (
                            str(row["trip_id"]),
                            ts,
                            str(row["route_short_name"])
                            if pd.notnull(row["route_short_name"])
                            else None,
                            str(row["trip_headsign"])
                            if pd.notnull(row["trip_headsign"])
                            else None,
                            float(row["latitude"])
                            if pd.notnull(row["latitude"])
                            else None,
                            float(row["longitude"])
                            if pd.notnull(row["longitude"])
                            else None,
                            int(row["delay_actual"])
                            if pd.notnull(row["delay_actual"])
                            else None,
                            str(row["state_position"])
                            if pd.notnull(row["state_position"])
                            else None,
                            int(row["vehicle_registration_number"])
                            if pd.notnull(row["vehicle_registration_number"])
                            else None,
                            int(row["is_canceled"]),
                        )
                    )

                skipped = 0
                try:
                    cursor.fast_executemany = True
                    cursor.executemany(insert_sql, records)
                except pyodbc.IntegrityError:
                    conn.rollback()
                    cursor.fast_executemany = False
                    for record in records:
                        try:
                            cursor.execute(insert_sql, record)
                        except pyodbc.IntegrityError:
                            skipped += 1
                    if skipped:
                        logging.warning("Skipped %d duplicate rows", skipped)
                conn.commit()

        inserted = len(records) - skipped
        return {
            "status": "success",
            "message": f"Successfully loaded {inserted} rows to SQL",
        }
    except Exception as e:
        logging.exception("Failed to load to SQL")
        return {"status": "error", "message": str(e)}


def run_pipeline():
    try:
        raw_data = extract()
        transformed_df = transform(raw_data)
        return load(transformed_df)
    except Exception as e:
        logging.exception("Pipeline execution error")
        return {"status": "error", "message": str(e)}


if __name__ == "__main__":
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    logging.basicConfig(level=logging.INFO, handlers=[handler])
    logging.getLogger("azure").setLevel(logging.WARNING)
    load_dotenv()
    print(run_pipeline())
