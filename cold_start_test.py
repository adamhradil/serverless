#!/usr/bin/env python3
import argparse
import json
import time
import urllib3
from datetime import datetime, timezone
from statistics import mean, median, stdev

from azure.identity import DefaultAzureCredential
from azure.mgmt.appcontainers import ContainerAppsAPIClient


def get_replica_count(aca_client, resource_group, app_name):
    try:
        app = aca_client.container_apps.get(resource_group, app_name)
        revision_name = app.latest_ready_revision_name
        if not revision_name:
            return 0
        replicas = aca_client.container_apps_revision_replicas.list_replicas(
            resource_group, app_name, revision_name
        )
        return len(replicas.value or [])
    except Exception as e:
        print(f"\n  [replica check error: {e}]")
        return None


def wait_for_scale_to_zero(
    aca_client, resource_group, app_name, max_wait=600, poll_interval=30
):
    elapsed = 0
    while elapsed < max_wait:
        count = get_replica_count(aca_client, resource_group, app_name)
        if count == 0:
            print(f"  Replicas: 0 - cold start confirmed (waited {elapsed}s)")
            return True
        if count is None:
            print("  Replica check failed - proceeding anyway")
            return False
        print(
            f"  Still warm ({count} replica), waiting {poll_interval}s... (elapsed {elapsed}s)",
            end="\r",
            flush=True,
        )
        time.sleep(poll_interval)
        elapsed += poll_interval

    print(f"  WARNING: app still warm after {max_wait}s - cold start may be inaccurate")
    return False


def trigger_run(http, fqdn, api_key):
    url = f"https://{fqdn}/run"
    t_start = time.monotonic()
    resp = http.request("POST", url, headers={"X-Api-Key": api_key}, timeout=120.0)
    wall_time = time.monotonic() - t_start
    return wall_time, json.loads(resp.data.decode())


def parse_result(wall_time, body, run_type, iteration):
    result = {
        "type": run_type,
        "iteration": iteration,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "wall_time_s": round(wall_time, 3),
        "status": body.get("status"),
    }

    logs = body.get("logs", [])
    if not logs:
        return result

    t_first = datetime.strptime(logs[0]["ts"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(
        tzinfo=timezone.utc
    )
    t_last = datetime.strptime(logs[-1]["ts"], "%Y-%m-%dT%H:%M:%S.%fZ").replace(
        tzinfo=timezone.utc
    )
    etl_duration = (t_last - t_first).total_seconds()

    result["etl_duration_s"] = round(etl_duration, 3)
    result["cold_start_s"] = round(wall_time - etl_duration, 3)
    result["log_count"] = len(logs)
    result["rows"] = next(
        (int(log["msg"].split()[1]) for log in logs if "Loading" in log["msg"]), None
    )

    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fqdn", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--subscription-id")
    parser.add_argument("--resource-group", default="benchmark-rg")
    parser.add_argument("--app-name", default="faas-benchmark-app")
    parser.add_argument("--iterations", type=int, default=10)
    parser.add_argument("--wait", type=int, default=600)
    parser.add_argument("--warm-runs", type=int, default=3)
    args = parser.parse_args()

    output_file = f"cold_start_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    http = urllib3.PoolManager()
    aca_client = ContainerAppsAPIClient(DefaultAzureCredential(), args.subscription_id)
    results = []

    print(f"output: {output_file}")

    for i in range(args.iterations):
        print(f"\niteration {i + 1}/{args.iterations} - waiting for scale-to-zero")
        wait_for_scale_to_zero(
            aca_client, args.resource_group, args.app_name, max_wait=args.wait
        )

        wall_time, body = trigger_run(http, args.fqdn, args.api_key)
        r = parse_result(wall_time, body, "cold", i + 1)
        results.append(r)
        print(
            f"cold: wall={r['wall_time_s']:.2f}s  overhead={r.get('cold_start_s', '?')}s"
        )

        for _ in range(args.warm_runs):
            wall_time, body = trigger_run(http, args.fqdn, args.api_key)
            r = parse_result(wall_time, body, "warm", i + 1)
            results.append(r)
            print(
                f"warm: wall={r['wall_time_s']:.2f}s  etl={r.get('etl_duration_s', '?')}s"
            )

    with open(output_file, "w") as f:
        json.dump(results, f, indent=2)

    cold = [
        r["cold_start_s"]
        for r in results
        if r["type"] == "cold" and "cold_start_s" in r
    ]
    warm = [
        r["etl_duration_s"]
        for r in results
        if r["type"] == "warm" and "etl_duration_s" in r
    ]
    if cold:
        print(
            f"\ncold start overhead (s): n={len(cold)} avg={mean(cold):.2f} med={median(cold):.2f} min={min(cold):.2f} max={max(cold):.2f}"
            + (f" std={stdev(cold):.2f}" if len(cold) > 1 else "")
        )
    if warm:
        print(
            f"warm etl duration (s):   n={len(warm)} avg={mean(warm):.2f} med={median(warm):.2f} min={min(warm):.2f} max={max(warm):.2f}"
            + (f" std={stdev(warm):.2f}" if len(warm) > 1 else "")
        )


if __name__ == "__main__":
    main()
