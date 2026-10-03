"""Bounded project-scoped Langfuse v2 reads; credentials and responses stay private."""
import base64
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import stat
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_BODY = 524_288
MAX_GETS = 20
MAX_POLL_SECONDS = 30
FIELDS = "core,basic,metadata,io,model,usage,trace_context"
METADATA_PROJECTION = "v4_flat_paths"
NAME_PROJECTION = "v4_gen_ai_tool_name_else_native"
EU = "https://cloud.langfuse.com"


class BoundaryError(Exception):
    """Fixed public failure codes; never include a remote body or secret value."""

    def __init__(self, code, *, facts=None):
        super().__init__(code)
        self.facts = facts


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def private_json(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write("\n")


def credentials(path):
    # Invoked only by an explicitly admitted run, never by default/preparation.
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise BoundaryError("credential_file_ownership_or_mode")
        raw = stream.read(4_097)
    if len(raw) > 4_096:
        raise BoundaryError("credential_file_limit")
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        raise BoundaryError("credential_file_json") from None
    if not isinstance(value, dict) or set(value) != {"public_key", "secret_key"}:
        raise BoundaryError("credential_file_fields")
    keys = [value[name] for name in ("public_key", "secret_key")]
    if any(not isinstance(key, str) or not 8 <= len(key.encode()) <= 256 or
           any(ord(c) < 33 or c == ":" for c in key) for key in keys):
        raise BoundaryError("credential_key_shape")
    token = base64.b64encode(":".join(keys).encode()).decode("ascii")
    return "Basic " + token


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        raise BoundaryError("api_redirect_refused")


def get_json(base, authorization, path, query, timeout):
    if base != EU:
        raise BoundaryError("unadmitted_backend")
    if path not in ("/api/public/projects", "/api/public/v2/observations"):
        raise BoundaryError("unadmitted_api_route")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(base + path + ("?" + urllib.parse.urlencode(query) if query else ""),
                                     headers={"Authorization": authorization, "Accept": "application/json"})
    try:
        with opener.open(request, timeout=timeout) as reply:
            if reply.status != 200:
                raise BoundaryError("api_non_200")
            raw = reply.read(MAX_BODY + 1)
    except urllib.error.HTTPError as error:
        # Authentication errors and response bodies are never emitted.
        raise BoundaryError("api_http_" + str(error.code)) from None
    except (urllib.error.URLError, OSError, TimeoutError):
        raise BoundaryError("api_transport") from None
    if len(raw) > MAX_BODY:
        raise BoundaryError("api_body_limit")
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        raise BoundaryError("api_json") from None
    return value, len(raw)


def client(base, authorization):
    return lambda query, timeout: get_json(base, authorization, "/api/public/v2/observations", query, timeout)


def project_scope(base, authorization, project):
    value, size = get_json(base, authorization, "/api/public/projects", {}, 2)
    return verify_project_scope(value, size, project)


def verify_project_scope(value, size, project):
    if not isinstance(value, dict) or not isinstance(value.get("data"), list) or len(value["data"]) != 1:
        raise BoundaryError("api_project_scope_shape")
    row = value["data"][0]
    if not isinstance(row, dict) or row.get("id") != project or row.get("name") != "exagent":
        raise BoundaryError("api_project_scope_mismatch")
    return {"status": "synthetic_project_key_verified", "project_id": project, "project_name": "exagent",
            "gets": 1, "body_bytes": size, "historical_traces_read": 0}


def attributes(row):
    metadata = row.get("metadata")
    # The official v4 worker flattens raw metadata into literal dotted names;
    # its public API preserves these names and JSON-decodes scalar values.
    # This is an explicit v4 projection, with no nested/string fallback.
    if not isinstance(metadata, dict):
        raise BoundaryError("api_attribute_projection", facts=projection_facts(metadata))
    actual = {key[len("attributes."):]: value for key, value in metadata.items() if key.startswith("attributes.")}
    resource = {key[len("resourceAttributes."):]: value for key, value in metadata.items() if key.startswith("resourceAttributes.")}
    if not actual:
        raise BoundaryError("api_attribute_projection", facts=projection_facts(metadata))
    return actual, resource


def projection_facts(metadata):
    """Whitelist shape facts only; keep this diagnostic separate from acceptance."""
    def shape(value):
        if value is None:
            return "null_or_missing"
        if isinstance(value, dict):
            return "object"
        if isinstance(value, list):
            return "array"
        if isinstance(value, str):
            return "string"
        if isinstance(value, bool):
            return "boolean"
        if isinstance(value, (int, float)):
            return "number"
        return "unknown"

    def encoded_shape(value):
        if not isinstance(value, str):
            return "not_a_string"
        if len(value.encode()) > 65536:
            return "diagnostic_byte_limit"
        try:
            return shape(json.loads(value))
        except (ValueError, RecursionError):
            return "not_complete_json"

    facts = {"metadata_type": shape(metadata), "metadata_json_type": encoded_shape(metadata)}
    for key in ("attributes", "resourceAttributes"):
        present = isinstance(metadata, dict) and key in metadata
        value = metadata.get(key) if isinstance(metadata, dict) else None
        facts[key + "_present"] = present
        facts[key + "_type"] = shape(value)
        facts[key + "_string_bytes"] = len(value.encode()) if isinstance(value, str) else 0
        facts[key + "_json_type"] = encoded_shape(value)
    return facts


def equal_scalar(actual, expected):
    if isinstance(expected, bool):
        return type(actual) is bool and actual == expected
    if isinstance(expected, float):
        return type(actual) in (float, int) and math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-6)
    return type(actual) is type(expected) and actual == expected


def expected_api_name(expected):
    """The official v4 extractName prioritizes a nonempty GenAI tool name.

    This admitted native profile has string tool names and no other naming
    integrations. Unknown native naming inputs fail before credentials access;
    an API row never supplies a fallback name or changes the native span name.
    """
    native = expected["attributes"]
    if any(key in native for key in ("genkit:name", "logfire.msg", "ai.toolCall.name", "ai.operationId")):
        raise BoundaryError("name_profile_native_schema")
    tool_name = native.get("gen_ai.tool.name")
    if tool_name is not None and not isinstance(tool_name, str):
        raise BoundaryError("name_profile_native_schema")
    return tool_name if tool_name else expected["name"]


def json_type(value):
    if value is None:
        return "null"
    if type(value) is bool:
        return "boolean"
    if type(value) is int:
        return "integer"
    if type(value) is float:
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    return "unknown"


def inspect_row(row, expected, trace, project, sentinels):
    """Run every oracle; retain only fixed labels, types, presence and matches.

    Diagnostics contain no API values, arbitrary metadata keys, content, usage
    amounts or remote IDs. The single row identity is from our native manifest.
    """
    failures, checks = [], {}

    def check(label, passed, code, *, container=None, key=None, applicable=True):
        fact = {"passed": bool(passed), "applicable": applicable}
        if key is not None:
            fact.update(present=isinstance(container, dict) and key in container,
                        json_type=json_type(container.get(key)) if isinstance(container, dict) else "missing")
        checks[label] = fact
        if applicable and not passed and code not in failures:
            failures.append(code)

    check("row_object", isinstance(row, dict), "api_trace_or_project")
    row = row if isinstance(row, dict) else {}
    for label, key, wanted in (("trace_identity", "traceId", trace["trace_id"]),
                               ("project_identity", "projectId", project)):
        check(label, key in row and equal_scalar(row.get(key), wanted), "api_trace_or_project", container=row, key=key)
    api_name = expected_api_name(expected)
    check("parent_identity", "parentObservationId" in row and equal_scalar(row.get("parentObservationId"), expected["parent_id"]),
          "api_parent_or_name", container=row, key="parentObservationId")
    check("name_projection", equal_scalar(row.get("name"), api_name), "api_parent_or_name", container=row, key="name")
    check("level", equal_scalar(row.get("level"), expected["level"]), "api_status_or_open_span", container=row, key="level")
    check("span_closed", bool(row.get("endTime")), "api_status_or_open_span", container=row, key="endTime")
    for label, key in (("startTime", "start_time_ms"), ("endTime", "end_time_ms")):
        matches = False
        try:
            milliseconds = round(datetime.fromisoformat(row[label].replace("Z", "+00:00")).timestamp() * 1_000)
            matches = milliseconds == expected[key]
        except (KeyError, ValueError, TypeError, AttributeError, OverflowError):
            pass
        check(label + "_native_ms", matches, "api_native_timestamp", container=row, key=label)
    for key in ("input", "output"):
        check(key + "_absent", key in row and row[key] in (None, ""), "api_content_not_absent", container=row, key=key)
    check("private_sentinels_absent", not any(sentinel in json.dumps(row, ensure_ascii=False) for sentinel in sentinels),
          "api_private_sentinel")
    try:
        actual, resource = attributes(row)
        projected = True
    except BoundaryError:
        actual, resource, projected = {}, {}, False
    check("metadata_v4_projection", projected, "api_attribute_projection", container=row, key="metadata")
    # All native attributes are examined even if an earlier row field failed.
    # Indices follow our manifest ordering; no metadata keys or values escape.
    native_diagnostics, verified_attributes = [], 0
    for key, wanted in expected["attributes"].items():
        if key.startswith("exagent.") or key.startswith("test."):
            present = key in actual
            matches = present and equal_scalar(actual[key], wanted)
            native_diagnostics.append({"present": present, "expected_type": json_type(wanted),
                                       "actual_type": json_type(actual.get(key)) if present else "missing",
                                       "matches": matches})
            verified_attributes += int(matches)
    check("all_native_attributes", verified_attributes == len(native_diagnostics), "api_native_attribute")
    for label, key in (("resource_true", "test.synthetic"), ("resource_false", "test.false")):
        check(label, key in resource and equal_scalar(resource[key], trace["resource_attributes"][key]),
              "api_resource_boolean", container=resource, key=key)
    model = expected["attributes"].get("exagent.operation") == "model"
    check("model_generation_type", row.get("type") == "GENERATION" if model else True,
          "api_model_mapping", container=row, key="type", applicable=model)
    check("model_identity", equal_scalar(row.get("model"), expected["attributes"].get("gen_ai.request.model")) if model else True,
          "api_model_mapping", container=row, key="model", applicable=model)
    usage = row.get("usageDetails")
    check("usage_object", isinstance(usage, dict) if model else True, "api_usage_projection",
          container=row, key="usageDetails", applicable=model)
    for label, key, field in (("usage_input_scalar", "gen_ai.usage.input_tokens", "input"),
                              ("usage_output_scalar", "gen_ai.usage.output_tokens", "output")):
        applicable = model and key in expected["attributes"]
        matches = (isinstance(usage, dict) and field in usage and equal_scalar(usage[field], expected["attributes"][key])) if applicable else True
        check(label, matches, "api_usage_mapping", container=usage, key=field, applicable=applicable)
    diagnostics = {"native_id": expected["id"], "checks": checks,
                   "native_attribute_checks": native_diagnostics, "mismatch_codes": failures}
    # Accepted facts retain native span name separately from its API projection.
    facts = {"id": expected["id"], "parent_id": expected["parent_id"], "name": api_name,
             "native_span_name": expected["name"], "name_projection": NAME_PROJECTION,
             "level": expected["level"], "native_attributes_verified": verified_attributes,
             "model_usage_projection_verified": model, "native_timestamps_preserved_ms": True,
             "input_output_absent": True, "resource_booleans_preserved": True}
    return (facts if not failures else None), diagnostics


def verify_row(row, expected, trace, project, sentinels):
    facts, diagnostics = inspect_row(row, expected, trace, project, sentinels)
    if facts is None:
        raise BoundaryError(diagnostics["mismatch_codes"][0], facts=diagnostics)
    return facts


def observation_query(trace):
    query = {"traceId": trace["trace_id"], "fromStartTime": trace["from_start_time"],
             "toStartTime": trace["to_start_time"], "fields": FIELDS, "limit": "32"}
    # Current SDK scalar strings are limited to 128 characters, below the API's
    # 200-character truncation threshold. If a later native manifest requires
    # expansion, request only its exact literal v4 keys, never wildcard keys.
    expand = {"attributes." + key for span in trace["spans"] for key, value in span["attributes"].items()
              if (key.startswith("exagent.") or key.startswith("test.")) and isinstance(value, str) and len(value) > 200}
    expand.update("resourceAttributes." + key for key in ("test.synthetic", "test.false")
                  if isinstance(trace["resource_attributes"].get(key), str) and len(trace["resource_attributes"][key]) > 200)
    if expand:
        query["expandMetadata"] = ",".join(sorted(expand))
    return query


def inspect_page(page, trace, project, sentinels):
    """Inspect a bounded page without leaking unknown IDs or arbitrary keys."""
    codes, page_checks, row_diagnostics = [], {}, []

    def check(label, passed, code):
        page_checks[label] = {"passed": bool(passed)}
        if not passed and code not in codes:
            codes.append(code)

    check("page_object", isinstance(page, dict), "api_page_shape")
    page = page if isinstance(page, dict) else {}
    rows = page.get("data")
    check("rows_array", isinstance(rows, list), "api_page_shape")
    check("rows_within_32", isinstance(rows, list) and len(rows) <= 32, "api_page_shape")
    check("no_pagination", isinstance(page.get("meta"), dict) and page["meta"].get("cursor") is None,
          "api_unexpected_pagination")
    rows = rows[:32] if isinstance(rows, list) else []
    wanted = {span["id"]: span for span in trace["spans"]}
    verified, observed = {}, set()
    identities = [row.get("id") if isinstance(row, dict) else None for row in rows]
    counts = {identity: identities.count(identity) for identity in identities if isinstance(identity, str)}
    for index, (row, identity) in enumerate(zip(rows, identities)):
        known = isinstance(identity, str) and identity in wanted
        unique = isinstance(identity, str) and counts[identity] == 1
        check("all_identities_known_unique", page_checks.get("all_identities_known_unique", {"passed": True})["passed"] and known and unique,
              "api_unexpected_or_duplicate_id")
        if known:
            observed.add(identity)
            facts, diagnostics = inspect_row(row, wanted[identity], trace, project, sentinels)
            diagnostics["checks"]["unique_native_identity"] = {"passed": unique, "applicable": True}
            if not unique:
                diagnostics["mismatch_codes"].append("api_unexpected_or_duplicate_id")
            if facts is not None and unique:
                verified[identity] = facts
        else:
            diagnostics = {"row_index": index, "checks": {
                "row_object": {"passed": isinstance(row, dict)},
                "native_identity_known": {"passed": False, "present": isinstance(row, dict) and "id" in row,
                                          "json_type": json_type(identity)}},
                "mismatch_codes": ["api_unexpected_or_duplicate_id"]}
        row_diagnostics.append(diagnostics)
        for code in diagnostics["mismatch_codes"]:
            if code not in codes:
                codes.append(code)
    return verified, {"checks": page_checks, "row_checks": row_diagnostics, "mismatch_codes": codes,
                      "rows_seen": len(rows), "native_identities_seen": len(observed),
                      "missing_native_ids": sorted(set(wanted) - observed)}


def verify_page(page, trace, project, sentinels):
    verified, diagnostics = inspect_page(page, trace, project, sentinels)
    if diagnostics["mismatch_codes"]:
        raise BoundaryError(diagnostics["mismatch_codes"][0], facts=diagnostics)
    return verified


def read_once(manifest, project, get, *, seconds=7):
    """One observation request per admitted trace; no polling or pagination."""
    traces = manifest["traces"]
    if not 0 < seconds <= 7 or len(traces) != 2 or any(not 1 <= len(t["spans"]) <= 32 for t in traces):
        raise BoundaryError("once_profile")
    started = time.monotonic()
    until = started + seconds
    seen = {trace["trace_id"]: {} for trace in traces}
    diagnostics, codes = {}, []
    gets, body_bytes = 0, 0
    for trace in traces:
        remaining = until - time.monotonic()
        if remaining <= 0:
            break
        gets += 1
        try:
            page, size = get(observation_query(trace), min(2, remaining))
            body_bytes += size
            seen[trace["trace_id"]], diagnostic = inspect_page(page, trace, project, manifest["sentinels"])
        except BoundaryError as error:
            diagnostic = {"mismatch_codes": [str(error)], "rows_seen": 0, "native_identities_seen": 0,
                          "missing_native_ids": [span["id"] for span in trace["spans"]], "row_checks": []}
        diagnostics[trace["trace_id"]] = diagnostic
        for code in diagnostic["mismatch_codes"]:
            if code not in codes:
                codes.append(code)
    missing = {t["trace_id"]: sorted({s["id"] for s in t["spans"]} - set(seen[t["trace_id"]])) for t in traces}
    status = "api_rows_not_qualified" if codes else "api_visibility_incomplete" if any(missing.values()) else "native_api_rows_verified_only"
    result = {"status": status,
              "gets": gets, "body_bytes": body_bytes, "poll_ms": round((time.monotonic() - started) * 1000),
              "ui_accepted": False, "no_poll_or_retry": True, "metadata_projection": METADATA_PROJECTION,
              "name_projection": NAME_PROJECTION, "diagnostics": diagnostics, "mismatch_codes": codes,
              "observations": {t: list(values.values()) for t, values in seen.items()}}
    if codes:
        result["code"] = codes[0]
    if any(missing.values()):
        result["missing"] = missing
    return result


def poll(manifest, project, get, *, seconds=MAX_POLL_SECONDS, interval=1.5, max_gets=MAX_GETS):
    if not (0 < seconds <= MAX_POLL_SECONDS and 1 <= max_gets <= MAX_GETS):
        raise BoundaryError("poll_profile")
    traces = manifest["traces"]
    if not 1 <= len(traces) <= 2 or any(not 1 <= len(t["spans"]) <= 32 for t in traces):
        raise BoundaryError("native_trace_budget")
    wanted = {t["trace_id"]: {s["id"]: s for s in t["spans"]} for t in traces}
    seen = {trace_id: {} for trace_id in wanted}
    until = time.monotonic() + seconds
    gets, body_bytes = 0, 0
    started = time.monotonic()
    while gets < max_gets and time.monotonic() < until:
        for trace in traces:
            trace_id = trace["trace_id"]
            if set(seen[trace_id]) == set(wanted[trace_id]):
                continue
            remaining = until - time.monotonic()
            if remaining <= 0 or gets >= max_gets:
                break
            query = observation_query(trace)
            page, size = get(query, min(2, remaining))
            gets += 1
            body_bytes += size
            seen[trace_id].update(verify_page(page, trace, project, manifest["sentinels"]))
        if all(set(seen[t]) == set(wanted[t]) for t in wanted):
            return {"status": "native_api_rows_verified_only", "gets": gets, "body_bytes": body_bytes,
                    "poll_ms": round((time.monotonic() - started) * 1000), "ui_accepted": False,
                    "observations": {t: list(seen[t].values()) for t in wanted}}
        remaining = until - time.monotonic()
        if remaining > 0:
            time.sleep(min(interval, remaining))
    return {"status": "api_visibility_incomplete", "gets": gets, "body_bytes": body_bytes,
            "poll_ms": round((time.monotonic() - started) * 1000), "ui_accepted": False,
            "missing": {t: sorted(set(wanted[t]) - set(seen[t])) for t in wanted}}
