"""严格汇总进程启动测量；缺失、失败和时钟异常样本不会伪装成达标。"""
import math
import statistics

METRICS = (
    "dart_main_us", "home_frame_us", "cache_visible_us",
    "recovery_rpc_started_us", "first_data_visible_us",
    "all_refresh_settled_us", "all_refresh_done_us",
    "five_sources_settled_us", "five_sources_done_us",
)
HOME_FEATURES = frozenset(('schedule', 'signin', 'spoc', 'judge', 'ygdk'))
HOME_SUPPLEMENT_SOURCES = frozenset(
    ('bykcChosen', 'cgyyOrders', 'currentWeek', 'gradeCheck'))
HOME_SOURCES = HOME_FEATURES | HOME_SUPPLEMENT_SOURCES


def validate(sample):
    errors = []
    start = sample.get("process_start_us")
    if not isinstance(start, int) or start <= 0:
        return ["missing_kernel_process_start"]
    if type(sample.get("business_writes")) is not int or sample["business_writes"] < 0:
        errors.append("missing_business_write_count")
    elif sample["business_writes"] != 0:
        errors.append("business_write_attempt")
    if sample.get("trace_truncated"):
        errors.append("trace_truncated")
    times = sample.get("times", {})
    for key, value in times.items():
        if not isinstance(value, int) or value < start:
            errors.append("clock_or_timestamp_invalid:" + key)
    for key in ("dart_main_us", "home_frame_us", "cache_visible_us", "recovery_rpc_started_us"):
        if key not in times:
            errors.append("missing:" + key)
    if ("home_frame_us" in times and "cache_visible_us" in times
            and times["home_frame_us"] > times["cache_visible_us"]):
        errors.append("cache_precedes_home")
    if 'all_refresh_done_us' in times:
        outcomes = sample.get('outcomes', {})
        feature_incomplete = any(
            outcomes.get(key, {}).get('complete') is not True
            or outcomes.get(key, {}).get('error') is not None
            for key in HOME_FEATURES)
        source_incomplete = any(
            outcomes.get(key, {}).get('finished') is not True
            or outcomes.get(key, {}).get('error') is not None
            or (key == 'gradeCheck' and
                outcomes.get(key, {}).get('check_complete') is not True)
            for key in HOME_SUPPLEMENT_SOURCES)
        if feature_incomplete or source_incomplete:
            errors.append('incomplete_home_coverage')
    return errors


def distribution(values, expected):
    values = sorted(values)
    return {
        "n": len(values), "missing": expected - len(values),
        "population_complete": len(values) == expected and expected > 0,
        "median_ms": statistics.median(values) if values else None,
        "p95_ms": values[math.ceil(0.95 * len(values)) - 1] if values else None,
        "min_ms": values[0] if values else None,
        "max_ms": values[-1] if values else None,
    }


def summarize(samples, planned=None):
    planned = len(samples) if planned is None else planned
    if type(planned) is not int or planned < len(samples):
        raise ValueError('计划样本数不得小于已启动数')
    valid = [s for s in samples if not validate(s)]
    metrics = {}
    for key in METRICS:
        values = [(s["times"][key] - s["process_start_us"]) / 1000
                  for s in valid if key in s["times"]]
        metrics[key.removesuffix("_us")] = distribution(values, planned)
    gaps = [(s["times"]["recovery_rpc_started_us"] - s["times"]["home_build_end_us"]) / 1000
            for s in valid if "home_build_end_us" in s["times"]]
    phase_cost = {}
    scheduler_cost = {"queued": 0, "started": 0, "completed": 0,
                      "cancelled": 0, "wait_ms": [], "run_ms": []}
    for sample_value in valid:
        for operation in sample_value.get("operations", []):
            phase = operation.get("phase")
            if phase is None:
                continue
            bucket = phase_cost.setdefault(phase, {
                "count": 0, "success": 0, "elapsed_ms": [],
            })
            bucket["count"] += 1
            bucket["success"] += int(operation.get("success") is True)
            bucket["elapsed_ms"].append(
                (operation.get("end_us", 0) - operation.get("start_us", 0)) / 1000
            )
        for trace in sample_value.get("scheduler_traces", []):
            kind = trace.get("kind")
            if kind in scheduler_cost:
                scheduler_cost[kind] += 1
            if kind == "completed":
                scheduler_cost["wait_ms"].append(trace.get("wait_us", 0) / 1000)
                scheduler_cost["run_ms"].append(trace.get("run_us", 0) / 1000)
    for bucket in phase_cost.values():
        values = sorted(bucket.pop("elapsed_ms"))
        bucket["median_ms"] = statistics.median(values) if values else None
        bucket["p95_ms"] = values[math.ceil(0.95 * len(values)) - 1] if values else None
    for key in ("wait_ms", "run_ms"):
        values = sorted(scheduler_cost[key])
        scheduler_cost[key] = {
            "n": len(values),
            "median_ms": statistics.median(values) if values else None,
            "p95_ms": values[math.ceil(0.95 * len(values)) - 1] if values else None,
        }
    origin_counts = {"persisted": 0, "online": 0, "mixed": 0, "unknown": 0}
    repeated = 0
    for sample_value in valid:
        names = [operation.get("operation") for operation in sample_value.get("operations", [])]
        repeated += sum(names.count(name) - 1 for name in set(names) if name is not None)
        for operation in sample_value.get("operations", []):
            origin = operation.get("origin") or "unknown"
            origin_counts[origin] = origin_counts.get(origin, 0) + 1
    return {
        "samples": len(samples), "valid": len(valid),
        "planned": planned, "not_started": planned - len(samples),
        "invalid": [{"index": i, "errors": validate(s)}
                    for i, s in enumerate(samples) if validate(s)],
        "fully_refreshed": sum("all_refresh_done_us" in s.get("times", {}) for s in valid),
        "metrics": metrics,
        "recovery_after_home_build": distribution(gaps, planned),
        "cost": {
            "phase": phase_cost,
            "scheduler": scheduler_cost,
            "origin_counts": origin_counts,
            "repeated_operation_count": repeated,
        },
        "p95_method": "nearest_rank",
        "clock": "kernel_process_birth_to_engine_raster_finish_wall_time",
    }
