#!/usr/bin/env python3
"""Offline fail-closed controls for the Opik API acceptance boundary."""
import argparse
import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import opik_api as api
from api import BoundaryError, digest, private_json


def timestamp(value):
    return datetime.fromtimestamp(value / 1000, timezone.utc).isoformat()


def fixtures(trace, project):
    mapping = api.identity_map(trace)
    rows = []
    for span in trace["spans"]:
        attrs = span["attributes"]
        model = attrs.get("exagent.operation") == "model"
        metadata = {**attrs, **{"resource." + k: v for k, v in trace["resource_attributes"].items()}}
        row = {"id": mapping["span_ids"][span["id"]], "trace_id": mapping["trace_id"],
               "project_id": project, "parent_span_id": mapping["span_ids"].get(span["parent_id"]),
               "name": span["name"], "type": "llm" if model else "general",
               "start_time": timestamp(span["start_time_ms"]), "end_time": timestamp(span["end_time_ms"]),
               "error_info": {"exception_type": "Error", "message": attrs.get("error.type"),
                              "traceback": attrs.get("error.type") or "Error"}
               if span["level"] == "ERROR" else None,
               "input": None, "output": None, "metadata": metadata, "usage": {}}
        if model:
            row.update(model=attrs["gen_ai.request.model"], provider=attrs["gen_ai.provider.name"],
                       usage={"prompt_tokens": attrs["gen_ai.usage.input_tokens"],
                              "completion_tokens": attrs["gen_ai.usage.output_tokens"],
                              "total_tokens": attrs["gen_ai.usage.input_tokens"] + attrs["gen_ai.usage.output_tokens"]})
        rows.append(row)
    return {"page": 1, "total": len(rows), "content": rows}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--manifest", type=Path)
    p.add_argument("--report", type=Path)
    args = p.parse_args()
    if not args.run:
        print("Skipped: explicit offline controls required. No network or credentials.")
        return
    manifest = json.loads(args.manifest.read_text())
    project = "00000000-0000-7000-8000-000000000001"
    checks = []
    for trace in manifest["traces"]:
        page = fixtures(trace, project)
        positive = api.inspect_page(page, trace, project, manifest["sentinels"])
        assert positive["status"] == "native_api_rows_verified_only"
        checks.append("all_native_rows_and_types_accepted")
        negatives = [
            ("missing_row", lambda p: p["content"].pop()),
            ("duplicate_row", lambda p: p["content"].__setitem__(0, copy.deepcopy(p["content"][1]))),
            ("unknown_id", lambda p: p["content"][0].update(id="00000000-0000-7000-8000-000000000009")),
            ("wrong_parent", lambda p: p["content"][0].update(parent_span_id="00000000-0000-7000-8000-000000000009")),
            ("wrong_trace", lambda p: p["content"][0].update(trace_id="00000000-0000-7000-8000-000000000009")),
            ("wrong_project", lambda p: p["content"][0].update(project_id="00000000-0000-7000-8000-000000000009")),
            ("wrong_name", lambda p: p["content"][0].update(name="PRIVATE_NAME_CANARY")),
            ("open_span", lambda p: p["content"][0].update(end_time=None)),
            ("wrong_error", lambda p: p["content"][0].update(error_info={"exception_type": "PRIVATE_ERROR_CANARY"})),
            ("content", lambda p: p["content"][0].update(input={"private": "PRIVATE_CONTENT_CANARY"})),
            ("sentinel", lambda p: p["content"][0].update(output=manifest["sentinels"][0])),
            ("resource_boolean", lambda p: p["content"][0]["metadata"].update({"resource.test.false": "false"})),
            ("inclusive_usage", lambda p: next(r for r in p["content"] if r["type"] == "general").update(usage={"total_tokens": 1})),
            ("wrong_type", lambda p: p["content"][0].update(type="PRIVATE_TYPE_CANARY")),
            ("pagination", lambda p: p.update(page=2)),
            ("hidden_extra_rows", lambda p: p.update(total=p["total"]+1)),
        ]
        model = next(i for i, r in enumerate(page["content"]) if r["type"] == "llm")
        negatives.extend([
            ("model_missing", lambda p: p["content"][model].pop("model")),
            ("provider_wrong", lambda p: p["content"][model].update(provider="PRIVATE_PROVIDER_CANARY")),
            ("usage_bool", lambda p: p["content"][model]["usage"].update(prompt_tokens=True)),
            ("usage_total", lambda p: p["content"][model]["usage"].update(total_tokens=999)),
            ("timestamp_ms", lambda p: p["content"][model].update(start_time=timestamp(trace["spans"][model]["start_time_ms"]+1))),
        ])
        for index, span in enumerate(trace["spans"]):
            for key, value in span["attributes"].items():
                if key.startswith("exagent.") or key.startswith("test."):
                    def change(p, i=index, k=key, v=value):
                        p["content"][i]["metadata"][k] = "PRIVATE_ATTRIBUTE_CANARY"
                    negatives.append(("native_attribute_type_and_value", change))
        for name, mutate in negatives:
            altered = copy.deepcopy(page)
            mutate(altered)
            result = api.inspect_page(altered, trace, project, manifest["sentinels"])
            assert result["status"] == "native_api_not_qualified", name
            # Failed diagnostics contain fixed labels/types/native facts only.
            text = json.dumps(result)
            assert "PRIVATE_" not in text and not any(s in text for s in manifest["sentinels"]), name
            checks.append(name)
        root = next(r for r in page["content"] if r["parent_span_id"] is None)
        remote_trace = {**root, "id": api.identity_map(trace)["trace_id"]}
        assert not api.inspect_trace(remote_trace, trace, project, manifest["sentinels"])["mismatch_codes"]
        remote_trace["id"] = project
        assert "api_trace_uuid" in api.inspect_trace(remote_trace, trace, project, manifest["sentinels"])["mismatch_codes"]
        checks.append("trace_projection_separate_uuid")
    for value in ({}, {"total": 2, "content": []},
                  {"total": 1, "content": [{"name": "other", "id": project}]},
                  {"total": 1, "content": [{"name": "exagent", "id": "private"}]}):
        try:
            api.verify_scope(value, 10, project, workspace="synthetic-workspace")
            raise AssertionError("wrong scope accepted")
        except BoundaryError:
            checks.append("wrong_scope_refused")
    result = {"status": "opik_offline_oracles_passed", "checks": len(checks),
              "check_labels": checks, "manifest_sha256": digest(args.manifest),
              "cloud_requests": 0, "credential_access": False}
    private_json(args.report, result)
    print(json.dumps({"status": result["status"], "checks": len(checks)}))


if __name__ == "__main__":
    main()
