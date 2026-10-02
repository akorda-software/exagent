#!/usr/bin/env python3
"""Opt-in API poll subprocess with a parent-owned absolute deadline."""
import argparse
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
from api import BoundaryError, client, credentials, poll, read_once, private_json, project_scope


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true")
    p.add_argument("--scope-only", action="store_true")
    p.add_argument("--once", action="store_true")
    p.add_argument("--seconds", type=float, default=30)
    p.add_argument("--max-gets", type=int, default=20)
    for name in ("manifest", "credentials-file", "report"):
        p.add_argument("--" + name, type=Path)
    p.add_argument("--project-id")
    p.add_argument("--base")
    args = p.parse_args()
    if not args.run:
        print("Skipped: opt in after an admitted wave. No credentials or network access.")
        return
    if not all((args.credentials_file, args.report, args.project_id, args.base)) or (not args.scope_only and not args.manifest):
        raise BoundaryError("missing_poll_admission")
    authorization = credentials(args.credentials_file)
    attempted = 0
    try:
        if args.scope_only:
            attempted = 1
            result = project_scope(args.base, authorization, args.project_id)
        else:
            manifest = json.loads(args.manifest.read_text())
            get = client(args.base, authorization)

            def counted_get(query, timeout):
                nonlocal attempted
                attempted += 1
                return get(query, timeout)

            if args.once:
                if args.max_gets != 2:
                    raise BoundaryError("once_get_budget")
                result = read_once(manifest, args.project_id, counted_get, seconds=args.seconds)
            else:
                result = poll(manifest, args.project_id, counted_get, seconds=args.seconds, max_gets=args.max_gets)
    except BoundaryError as error:
        # Only locally defined failure codes are retained, never a remote row,
        # response body, header, exception value, or credential.
        failure = {"status": "api_failed_private_boundary", "code": str(error),
                   "api_request_attempts": attempted, "ui_accepted": False}
        if error.facts is not None:
            failure["boundary_facts"] = error.facts
        private_json(args.report, failure)
        raise
    private_json(args.report, result)
    print(json.dumps({"status": result["status"], "gets": result["gets"], "ui_accepted": False}))


if __name__ == "__main__":
    try:
        main()
    except BoundaryError as error:
        print(json.dumps({"status": "failed", "code": str(error)}))
        raise SystemExit(1)
    except Exception:
        print('{"status":"failed","code":"private_poll_failure"}')
        raise SystemExit(1)
