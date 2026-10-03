# Opt-in framework consumer profiles

Run `python3 -I test/support/framework_integrations/run.py --list` to list
`liveview`, `oban-postgres`, and `all` without launching processes or making
network requests. Execution requires an explicit physical core freeze, isolated
Hex/Rebar archives, native PostgreSQL bin directory and an artifact parent whose
Unix socket path fits within 90 bytes.

The complete host callback/wiring, command, authority boundaries and qualified
limits are in [framework-integrations.md](../../../docs/development/framework-integrations.md).
Both profiles use real framework packages and a fresh private SQL cluster;
compile/preparation failures and missing observations fail closed. Ordinary
offline ExAgent tests do not discover the consumer's `test/cases.exs`.
