"""Finite native/API oracles for the explicitly admitted synthetic Opik project.

Only fixed failure labels and native facts leave a response boundary. Remote
bodies, unexpected keys/IDs and credentials are neither logged nor persisted.
"""
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import urllib.error
import urllib.parse
import urllib.request
import uuid

from api import BoundaryError, NoRedirect, equal_scalar, json_type

BASE = "https://www.comet.com/opik"
PROJECT = "exagent"
MAX_BODY = 524_288
PROJECTION = "opik_metadata_native_v1"


def require(test, code):
    if not test:
        raise BoundaryError(code)


def credentials(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o600 and
                info.st_uid == os.getuid(), "credential_file_ownership_or_mode")
        raw = stream.read(4097)
    require(len(raw) <= 4096, "credential_file_limit")
    try:
        value = json.loads(raw)
    except (ValueError, UnicodeError):
        raise BoundaryError("credential_file_json") from None
    require(isinstance(value, dict) and set(value) == {"api_key"}, "credential_file_fields")
    key = value["api_key"]
    require(isinstance(key, str) and 8 <= len(key.encode()) <= 256 and
            all(33 <= ord(c) < 127 for c in key), "credential_key_shape")
    return key


def valid_uuid(value):
    return isinstance(value, str) and bool(re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", value))


def get_json(authorization, path, query=None, *, workspace, timeout=2, max_body=MAX_BODY):
    require(isinstance(workspace, str) and bool(re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", workspace)),
            "unadmitted_workspace")
    require(path in ("/api/v1/private/projects", "/api/v1/private/spans") or
            (path.startswith("/api/v1/private/traces/") and valid_uuid(path.rsplit("/", 1)[1])),
            "unadmitted_api_route")
    request = urllib.request.Request(BASE + path + ("?" + urllib.parse.urlencode(query) if query else ""),
                                     headers={"Authorization": authorization, "Comet-Workspace": workspace,
                                              "Accept": "application/json"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(request, timeout=timeout) as response:
            require(response.status == 200, "api_non_200")
            raw = response.read(max_body + 1)
    except urllib.error.HTTPError as error:
        raise BoundaryError("api_http_" + str(error.code)) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise BoundaryError("api_transport") from None
    require(len(raw) <= max_body, "api_body_limit")
    try:
        return json.loads(raw), len(raw)
    except (ValueError, UnicodeError):
        raise BoundaryError("api_json") from None


def verify_scope(value, size, project_id=None, *, workspace):
    require(isinstance(value, dict) and type(value.get("total")) is int and value["total"] == 1 and
            isinstance(value.get("content"), list) and len(value["content"]) == 1, "api_project_scope_shape")
    row = value["content"][0]
    require(isinstance(row, dict) and row.get("name") == PROJECT and valid_uuid(row.get("id")) and
            (project_id is None or row["id"] == project_id), "api_project_scope_mismatch")
    return {"status": "synthetic_workspace_project_verified", "project_id": row["id"],
            "project_name": PROJECT, "workspace": workspace, "gets": 1,
            "body_bytes": size, "historical_traces_read": 0, "account_key_not_project_key": True}


def scope(authorization, project_id=None, *, workspace):
    value, size = get_json(authorization, "/api/v1/private/projects",
                           {"name": PROJECT, "page": "1", "size": "2"}, workspace=workspace, max_body=65_536)
    return verify_scope(value, size, project_id, workspace=workspace)


def mapped_id(native_hex, timestamp_ms):
    # Pinned official OpenTelemetryMapper.convertOtelIdToUUIDv7; this is an ID
    # oracle, not an OTLP parser, wire encoder or backend ID override.
    raw = bytearray(int(timestamp_ms).to_bytes(6, "big") + hashlib.sha256(bytes.fromhex(native_hex)).digest()[:10])
    raw[6] = (raw[6] & 15) | 112
    raw[8] = (raw[8] & 63) | 128
    return str(uuid.UUID(bytes=bytes(raw)))


def identity_map(trace):
    timestamp = min(s["start_time_ms"] for s in trace["spans"])
    return {"trace_id": mapped_id(trace["trace_id"], timestamp),
            "span_ids": {s["id"]: mapped_id(s["id"], timestamp) for s in trace["spans"]},
            "timestamp_ms": timestamp}


def inspect_row(row, expected, trace, project_id, sentinels):
    checks, codes = {}, []

    def check(label, good, code):
        checks[label] = {"passed": bool(good)}
        if not good and code not in codes:
            codes.append(code)

    check("row_object", isinstance(row, dict), "api_row_shape")
    row = row if isinstance(row, dict) else {}
    mapping = identity_map(trace)
    check("native_uuid_id", row.get("id") == mapping["span_ids"][expected["id"]], "api_uuid_mapping")
    check("trace_project", row.get("trace_id") == mapping["trace_id"] and
          row.get("project_id") == project_id, "api_trace_or_project")
    parent = mapping["span_ids"].get(expected["parent_id"])
    check("parent_name", row.get("parent_span_id") == parent and row.get("name") == expected["name"],
          "api_parent_or_name")
    for label in ("start", "end"):
        try:
            value = round(datetime.fromisoformat(row[label + "_time"].replace("Z", "+00:00")).timestamp() * 1000)
            good = value == expected[label + "_time_ms"]
        except (KeyError, TypeError, AttributeError, ValueError, OverflowError):
            good = False
        check(label + "_native_ms", good, "api_native_timestamp")
    error = row.get("error_info")
    check("error_status", (isinstance(error, dict) and error.get("exception_type") == "Error")
          if expected["level"] == "ERROR" else error in (None, {}), "api_error_status")
    if expected["level"] == "ERROR":
        # Core sets the native status message to its redacted error.type label;
        # the pinned mapper copies that message to message/traceback. Do not
        # accept arbitrary response text merely because exception_type is Error.
        error = error if isinstance(error, dict) else {}
        message = expected["attributes"].get("error.type")
        check("error_diagnostic_only", set(error) <= {"exception_type", "message", "traceback"} and
              equal_scalar(error.get("message"), message) and
              equal_scalar(error.get("traceback"), message or "Error"), "api_content_not_absent")
    for field in ("input", "output"):
        check(field + "_empty", row.get(field) in (None, {}, ""), "api_content_not_absent")
    check("private_sentinels_absent", not any(s in json.dumps(row, ensure_ascii=False) for s in sentinels),
          "api_private_sentinel")
    metadata = row.get("metadata")
    check("metadata_object", isinstance(metadata, dict), "api_metadata_projection")
    metadata = metadata if isinstance(metadata, dict) else {}
    check("content_namespace_absent", not any(
        k.startswith("exagent.content.") or k.startswith("resource.exagent.content.") for k in metadata),
        "api_content_not_absent")
    facts = []
    for key, wanted in expected["attributes"].items():
        good = key in metadata and equal_scalar(metadata[key], wanted)
        facts.append({"present": key in metadata, "matches": good,
                      "expected_type": json_type(wanted), "actual_type": json_type(metadata.get(key))})
    check("all_native_attributes", all(f["matches"] for f in facts), "api_native_attribute")
    check("resource_attributes", all(key in metadata and equal_scalar(metadata[key], wanted)
          for key, wanted in (("resource." + k, v) for k, v in trace["resource_attributes"].items())),
          "api_resource_attribute")
    model = expected["attributes"].get("exagent.operation") == "model"
    check("semantic_type", row.get("type") == ("llm" if model else "general"), "api_span_type")
    if model:
        check("model_identity", row.get("model") == expected["attributes"]["gen_ai.request.model"],
              "api_model_mapping")
        check("provider_identity", row.get("provider") == expected["attributes"]["gen_ai.provider.name"],
              "api_provider_mapping")
        usage = row.get("usage")
        usage = usage if isinstance(usage, dict) else {}
        for native, api in (("gen_ai.usage.input_tokens", "prompt_tokens"),
                            ("gen_ai.usage.output_tokens", "completion_tokens")):
            check(api, api in usage and equal_scalar(usage[api], expected["attributes"][native]), "api_usage_mapping")
        check("total_tokens", equal_scalar(usage.get("total_tokens"),
              expected["attributes"]["gen_ai.usage.input_tokens"] + expected["attributes"]["gen_ai.usage.output_tokens"]),
              "api_usage_mapping")
    else:
        check("no_inclusive_double_count", row.get("usage") in (None, {}), "api_parent_usage")
    # Cost/usage quality, provenance and units are among the exact native attrs;
    # Opik's separately estimated total_estimated_cost is never a billing oracle.
    return {"native_id": expected["id"], "checks": checks, "native_attribute_checks": facts,
            "mismatch_codes": codes, "native_attributes_verified": sum(f["matches"] for f in facts),
            "model_usage_verified": model and not codes}


def inspect_page(page, trace, project_id, sentinels):
    mapping = identity_map(trace)
    expected = {mapping["span_ids"][s["id"]]: s for s in trace["spans"]}
    codes, diagnostics = [], []
    shape = (isinstance(page, dict) and isinstance(page.get("content"), list) and
             type(page.get("total")) is int and page["total"] == len(expected) and
             type(page.get("page")) is int and page["page"] == 1 and
             len(page["content"]) == len(expected) <= 32)
    if not shape:
        codes.append("api_page_shape_or_missing")
    rows = page.get("content", []) if isinstance(page, dict) else []
    rows = rows[:32] if isinstance(rows, list) else []
    observed = set()
    for row in rows:
        identity = row.get("id") if isinstance(row, dict) else None
        if not isinstance(identity, str) or identity not in expected or identity in observed:
            codes.append("api_unknown_or_duplicate_id")
            continue
        observed.add(identity)
        result = inspect_row(row, expected[identity], trace, project_id, sentinels)
        diagnostics.append(result)
        codes.extend(result["mismatch_codes"])
    if observed != set(expected):
        codes.append("api_missing_native_id")
    return {"status": "native_api_rows_verified_only" if not codes else "native_api_not_qualified",
            "mismatch_codes": list(dict.fromkeys(codes)), "rows": diagnostics,
            "observations_verified": len(diagnostics) if not codes else 0,
            "api_trace_id": mapping["trace_id"], "native_trace_id": trace["trace_id"]}


def inspect_trace(row, trace, project_id, sentinels):
    root = next(s for s in trace["spans"] if s["parent_id"] is None)
    check = dict(row) if isinstance(row, dict) else {}
    # Trace schema has no parent/type/model/usage; it is a separate projection of
    # the application root. Exact total usage comes from the 12 leaf spans.
    check.update(id=identity_map(trace)["span_ids"][root["id"]],
                 trace_id=identity_map(trace)["trace_id"], parent_span_id=None, type="general", usage={})
    result = inspect_row(check, root, trace, project_id, sentinels)
    if not isinstance(row, dict) or row.get("id") != identity_map(trace)["trace_id"]:
        result["mismatch_codes"].append("api_trace_uuid")
    return result
