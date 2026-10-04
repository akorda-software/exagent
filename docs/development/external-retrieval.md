# Retrieve external data through a tool

The packaged [external_retrieval.exs](https://github.com/akorda-software/exagent/blob/main/examples/external_retrieval.exs)
recipe injects an application search function through public ExAgent APIs.
The application chooses its search service, database, cache and authorization.

## Bind the caller's scope

Authenticate the caller and pass `deps: %{space: space, search: search}`.
The callback `search.(space, query, limit)` returns `{:ok, hits}` or
`{:error, reason}`. It must enforce the supplied space in the actual data source.
The model can supply only `query`; an extra space selector rejects before IO.

## Bound returned passages

The recipe admits at most three results with unique references:

| Field | Contract |
|---|---|
| `reference` | UTF-8 string, 1–512 bytes. |
| `text` | UTF-8 string, at most 2,048 bytes. |

Malformed or oversized results reject as a whole. Bound downloads/decoding inside
the external client too; validating returned data cannot limit allocations that
already happened while receiving it.

Passages become `ToolReturn` content in canonical history. They are not system
instructions, permission grants, approval actors or credentials. Continue to
enforce the run's authority and your source's access control.

## Handle source failures

Callback errors, exceptions and catchable throws/exits map to
`retrieval_unavailable`. Private source responses, headers and connection settings
are not copied into tool results or error messages. The example performs no
automatic source retry. Reconcile any uncertain external effect separately.

Run the deterministic example locally:

```bash
EXAGENT_OFFLINE=1 MIX_ENV=test mix run examples/external_retrieval.exs
```

Verify your real search adapter's authorization, response limits and failure
handling separately. Returning passages does not establish resistance to prompt
injection; retrieved text remains untrusted application input.
