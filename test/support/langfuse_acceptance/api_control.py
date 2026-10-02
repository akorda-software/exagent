#!/usr/bin/env python3
"""Offline v4 API fixture: full native pair, all-check diagnostics and negatives."""
import argparse
import copy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
from api import (BoundaryError, FIELDS, METADATA_PROJECTION, NAME_PROJECTION, digest,
                 expected_api_name, observation_query, private_json, read_once)
from run import tree_hashes

PROJECT = "cmujo5tsd08uiad0cqi6bw9ag"


def timestamp(milliseconds):
    return datetime.fromtimestamp(milliseconds / 1000, timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def rows_for(trace):
    rows = []
    for span in trace["spans"]:
        native = span["attributes"]
        # Public v4 extractName gives a nonempty GenAI tool name precedence.
        # This fixture deliberately does not call the oracle's name helper.
        tool_name = native.get("gen_ai.tool.name")
        row = {"id": span["id"], "traceId": trace["trace_id"], "projectId": PROJECT,
               "parentObservationId": span["parent_id"], "name": tool_name if tool_name else span["name"],
               "level": span["level"], "startTime": timestamp(span["start_time_ms"]),
               "endTime": timestamp(span["end_time_ms"]), "input": None, "output": None,
               "metadata": {**{"attributes." + key: value for key, value in native.items()},
                            **{"resourceAttributes." + key: value for key, value in trace["resource_attributes"].items()}}}
        if native.get("exagent.operation") == "model":
            row.update(type="GENERATION", model=native["gen_ai.request.model"], usageDetails={
                field: native[key] for key, field in (("gen_ai.usage.input_tokens", "input"),
                                                     ("gen_ai.usage.output_tokens", "output")) if key in native})
        rows.append(row)
    return rows


def exercise(manifest, pages):
    queries = []
    by_trace = {trace["trace_id"]: trace for trace in manifest["traces"]}

    def get(query, timeout):
        assert query == observation_query(by_trace[query["traceId"]]) and timeout <= 2
        assert query["fields"] == "core,basic,metadata,io,model,usage,trace_context"
        assert query["limit"] == "32" and "cursor" not in query
        queries.append(query)
        page = copy.deepcopy(pages[query["traceId"]])
        # The published API excludes model without its field group and truncates
        # long metadata strings unless the exact literal stored key is expanded.
        for row in page.get("data", []):
            if not isinstance(row, dict):
                continue
            if "model" not in query["fields"].split(","):
                row.pop("model", None)
            expanded = query.get("expandMetadata", "").split(",")
            if isinstance(row.get("metadata"), dict):
                for key, value in list(row["metadata"].items()):
                    if isinstance(value, str) and len(value) > 200 and key not in expanded:
                        row["metadata"][key] = value[:200]
        return page, len(json.dumps(page).encode())

    result = read_once(manifest, PROJECT, get)
    assert len(queries) == 2 and {q["traceId"] for q in queries} == set(by_trace)
    assert result["gets"] == 2 and result["no_poll_or_retry"] is True
    return result, queries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    if not args.run:
        print("Skipped: explicit offline control required. No credentials or network access.")
        return
    assert args.manifest and args.work
    os.umask(0o077)
    manifest = json.loads(args.manifest.read_text())
    assert len(manifest["traces"]) == 2 and sum(len(t["spans"]) for t in manifest["traces"]) == 33
    pages = {trace["trace_id"]: {"data": rows_for(trace), "meta": {"cursor": None}} for trace in manifest["traces"]}
    positive, queries = exercise(manifest, pages)
    rows = [row for page in pages.values() for row in page["data"]]
    diagnostics = [row for page in positive["diagnostics"].values() for row in page["row_checks"]]
    accepted = [row for trace in positive["observations"].values() for row in trace]
    assert positive["status"] == "native_api_rows_verified_only" and len(accepted) == 33
    assert len(diagnostics) == 33 and all(not row["mismatch_codes"] for row in diagnostics)
    assert all(all(check["passed"] for check in row["checks"].values()) for row in diagnostics)
    assert sum(row["model_usage_projection_verified"] for row in accepted) == 12
    assert sum(row["name"] != row["native_span_name"] for row in accepted) == 4
    first = manifest["traces"][0]["trace_id"]
    second = manifest["traces"][1]["trace_id"]
    tool_index = next(i for i, span in enumerate(manifest["traces"][0]["spans"]) if span["attributes"].get("gen_ai.tool.name"))
    model_index = next(i for i, span in enumerate(manifest["traces"][0]["spans"]) if span["attributes"].get("exagent.operation") == "model")
    bool_index, bool_key = next((i, "attributes." + key) for i, span in enumerate(manifest["traces"][0]["spans"])
                                for key, value in span["attributes"].items()
                                if type(value) is bool and (key.startswith("test.") or key.startswith("exagent.")))
    integer_index, integer_key = next((i, "attributes." + key) for i, span in enumerate(manifest["traces"][0]["spans"])
                                      for key, value in span["attributes"].items()
                                      if type(value) is int and (key.startswith("test.") or key.startswith("exagent.")))
    negative_cases = [
        ("api_parent_or_name", lambda p: p[first]["data"][tool_index].update(name=manifest["traces"][0]["spans"][tool_index]["name"])),
        ("api_parent_or_name", lambda p: p[first]["data"][tool_index].update(name="WRONG_REMOTE_NAME")),
        ("api_parent_or_name", lambda p: p[first]["data"][tool_index].update(parentObservationId=None)),
        ("api_status_or_open_span", lambda p: p[first]["data"][model_index].update(level="ERROR")),
        ("api_status_or_open_span", lambda p: p[first]["data"][model_index].update(endTime=None)),
        ("api_native_timestamp", lambda p: p[first]["data"][model_index].update(startTime="2026-10-02T00:00:00Z")),
        ("api_native_attribute", lambda p: p[first]["data"][bool_index]["metadata"].update({bool_key: "false"})),
        ("api_native_attribute", lambda p: p[first]["data"][integer_index]["metadata"].update({integer_key: float(p[first]["data"][integer_index]["metadata"][integer_key])})),
        ("api_native_attribute", lambda p: p[first]["data"][integer_index]["metadata"].pop(integer_key)),
        ("api_resource_boolean", lambda p: p[first]["data"][0]["metadata"].update({"resourceAttributes.test.false": "false"})),
        ("api_model_mapping", lambda p: p[first]["data"][model_index].update(type="SPAN")),
        ("api_model_mapping", lambda p: p[first]["data"][model_index].pop("model")),
        ("api_usage_projection", lambda p: p[first]["data"][model_index].update(usageDetails="{\"input\":3}")),
        ("api_usage_mapping", lambda p: p[first]["data"][model_index]["usageDetails"].update(input=True)),
        ("api_content_not_absent", lambda p: p[first]["data"][0].update(input="DO_NOT_RETAIN_CONTENT_CANARY")),
        ("api_private_sentinel", lambda p: p[first]["data"][0].update(statusMessage=manifest["sentinels"][0])),
        ("api_trace_or_project", lambda p: p[first]["data"][0].update(projectId="DO_NOT_RETAIN_PROJECT_CANARY")),
        ("api_trace_or_project", lambda p: p[first]["data"][0].update(traceId="DO_NOT_RETAIN_TRACE_CANARY")),
        ("api_attribute_projection", lambda p: p[first]["data"][0].update(metadata={"attributes": {"test.synthetic": True}})),
        ("api_attribute_projection", lambda p: p[first]["data"][0].update(metadata=json.dumps(p[first]["data"][0]["metadata"]))),
        ("api_unexpected_or_duplicate_id", lambda p: p[first]["data"][1].update(id=p[first]["data"][0]["id"])),
        ("api_unexpected_or_duplicate_id", lambda p: p[first]["data"][0].update(id="DO_NOT_RETAIN_ID_CANARY")),
        ("api_unexpected_pagination", lambda p: p[first]["meta"].update(cursor="DO_NOT_RETAIN_CURSOR_CANARY")),
    ]
    codes = []
    for code, mutate in negative_cases:
        changed = copy.deepcopy(pages)
        mutate(changed)
        result, _ = exercise(manifest, changed)
        assert result["status"] == "api_rows_not_qualified" and code in result["mismatch_codes"], (code, result["mismatch_codes"])
        encoded = json.dumps(result)
        assert "DO_NOT_RETAIN" not in encoded and not any(value in encoded for value in manifest["sentinels"])
        assert len(result["diagnostics"][second]["row_checks"]) == 18
        codes.append(code)
    # One page can fail several unrelated oracles; every check and both queries
    # still execute, without another cloud call per field.
    many = copy.deepcopy(pages)
    many[first]["data"][tool_index].update(name="DO_NOT_RETAIN_NAME_CANARY", parentObservationId=None,
                                         level="DO_NOT_RETAIN_LEVEL_CANARY", input="DO_NOT_RETAIN_INPUT_CANARY")
    many[first]["data"][bool_index]["metadata"][bool_key] = "false"
    many[second]["data"][0]["metadata"]["resourceAttributes.test.false"] = "false"
    many[first]["data"][tool_index]["metadata"]["DO_NOT_RETAIN_ARBITRARY_KEY"] = "DO_NOT_RETAIN_ARBITRARY_VALUE"
    many_result, _ = exercise(manifest, many)
    assert {"api_parent_or_name", "api_status_or_open_span", "api_content_not_absent",
            "api_native_attribute", "api_resource_boolean"} <= set(many_result["mismatch_codes"])
    assert "DO_NOT_RETAIN" not in json.dumps(many_result)
    assert sum(len(page["row_checks"]) for page in many_result["diagnostics"].values()) == 33
    missing = copy.deepcopy(pages)
    missing[first]["data"].pop()
    incomplete, _ = exercise(manifest, missing)
    assert incomplete["status"] == "api_visibility_incomplete" and sum(len(ids) for ids in incomplete["missing"].values()) == 1
    expanded_manifest = copy.deepcopy(manifest)
    expanded_manifest["traces"][0]["spans"][0]["attributes"]["test.control.long_value"] = "L" * 220
    expanded_pages = {trace["trace_id"]: {"data": rows_for(trace), "meta": {"cursor": None}} for trace in expanded_manifest["traces"]}
    expanded, expanded_queries = exercise(expanded_manifest, expanded_pages)
    assert expanded["status"] == "native_api_rows_verified_only"
    assert expanded_queries[0]["expandMetadata"] == "attributes.test.control.long_value" and "expandMetadata" not in expanded_queries[1]
    bad_name = copy.deepcopy(manifest["traces"][0]["spans"][0])
    bad_name["attributes"]["gen_ai.tool.name"] = 7
    try:
        expected_api_name(bad_name)
    except BoundaryError as error:
        assert str(error) == "name_profile_native_schema"
    else:
        raise AssertionError("nonstring_tool_name_not_admitted")
    work = Path(tempfile.mkdtemp(prefix="api-v4-name-control-", dir=args.work))
    report = {"status": "official_v4_and_name_projection_verified_offline_only", "driver_sha256": digest(__file__),
              "native_manifest_sha256": digest(args.manifest), "source_hashes": tree_hashes(Path(__file__).resolve().parent),
              "metadata_projection": METADATA_PROJECTION, "name_projection": NAME_PROJECTION,
              "positive_queries": queries, "positive_gets": 2, "native_rows": 33, "model_usage_rows": 12,
              "semantic_tool_name_rows": 4, "negative_codes": codes, "all_rows_all_checks_diagnostics": True,
              "all_checks_with_multiple_failures_on_both_traces": True, "missing_rows_red_without_poll": True,
              "exact_literal_expansion_only_if_required": True, "native_span_name_preserved": True,
              "unknown_native_name_profile_rejected_before_keys": True,
              "diagnostics_contain_remote_values_or_arbitrary_keys": False,
              "real_credentials_read": False, "authenticated_gets": 0, "cloud_posts": 0,
              "producer_sdk_collector_model_reruns": 0, "ui_accepted": False}
    private_json(work / "report.json", report)
    print(json.dumps({"status": report["status"], "report": str(work / "report.json"), "sha256": digest(work / "report.json")}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print('{"status":"failed","code":"private_api_control_failure"}')
        raise SystemExit(1)
