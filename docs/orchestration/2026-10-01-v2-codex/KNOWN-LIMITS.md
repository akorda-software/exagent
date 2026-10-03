# Known-limit treatment — 2026-10-03

User requests time on the two remaining limits after the documentation pass.
Root baseline: `63f3fe31a8974e7c1d1c7ba7b28afb616013e958`. No new independent
review or publication authorization. Official stock ReqLLM1.26 only.

## Native receipt hypothesis and controls

The application's Receipt requires only items; merchant/currency are nullable.
Public `OutputSchema.json_schema/1` and `validate/2` reproduce that acceptance.
A controlled changeset requiring the two headers rejects null and accepts the
complete fixture. The first inspection helper assumed an error `path` field;
the public output-validation error uses `field`. Original failed helper retained.

Do not change the demo's intentional partial extraction. The final test-only
`ChatApp.E2E.NativeReceipt` declares the E2E requirement, and Support selects it
only for native output. The shared oracle accepts the two named Ecto structs
with identical value/item assertions. The receipt records the actual schema name.
No prompt, model option, source ticket, retry or library runtime change.

| Wave | Model | Actual result | Admissions | Phase total |
|---|---|---|---:|---:|
| native-required-deepseek | DeepSeek V4.1 Flash | Same prompt/oracle passes with required header |1|55|
| native-required-luna | GPT-6-Luna | Same control passes |1|52|
| native-nullable-reversal | DeepSeek | Same prompt/oracle fails again with null header; child exit2, driver1 |1|56|
| native-final-deepseek | DeepSeek | Actual final NativeReceipt08 passes; receipt verified |1|57|
| native-final-luna | Luna | Actual final NativeReceipt08 passes; receipt verified |1|53|

Every group closes, sources remain unchanged within each wave, no credential
retained. Five new admissions reserve USD0.125; invoice null. The original phase
ledgers are appended, not reset/refunded: DeepSeek57/60, USD1.425; Luna53/60,
USD1.325. Complex ledgers remain independent. Original nullable errors and
[E2E-MODELS](E2E-MODELS.md) / [E2E-COMPLEX](E2E-COMPLEX.md) retain their identities.

Offline consumer precommit passes20 cases/zero failures/27 excluded, including
three new public schema/validation regressions. Fifty-two code/config/script/lock
inputs (*.ex/*.exs/*.py plus manifests) match the authorized consumer WIP;
all95 library/config/Mix/lock inputs match the live freeze before root doc edits.
Application lib/.env remain unchanged; consumer commit remains unauthorized.

Combined scenario coverage is27/27 per model by reusing26 unaffected cases and
qualifying the new08. Not a complete new wave, statistical determinism, arbitrary
JSON-schema/provider qualification or acceptance of the old nullable extraction.
Required fields prevent local acceptance of absence; semantic value checks remain.

## Dependency warning investigation

Fresh official Hex API queries confirm TOML0.7.0, WebSockex0.5.1, gproc1.3.0 and
grpcbox0.18.0. grpcbox requires `~>1.2.0`; official gproc1.3 TAR checksum verified:
`143a8ce6eb59610a351178482b629d2b052c69df84c9c50b9c13ae38354c8c14`.
That source uses filtermap in place of deprecated lists:zf. It is inspected only,
not installed, overridden or vendored into ExAgent.

The prior compiler receipt sources are equal to current deps:11 TOML,8 WebSockex,
15 gproc files. Reuse the identified diagnostic instead of a new full compilation
of unchanged third-party sources. Categorization:15 TOML charlist deprecations,
four unreachable datetime branches,19 WebSockex bit-size warnings (some duplicate
locations), eight gproc subexpression-binding warnings and one lists:zf deprecation.

- TOML charlist PR43 merged2025-10-10; latest Hex is still0.7.0. That fix alone
  does not establish removal of the four unreachable-branch warnings.
- WebSockex stable0.5.1 is unchanged; ReqLLM's WebSocket session is distinct from
  ExAgent's qualified HTTP/SSE profile. No realtime qualification is inferred.
- Gproc PR206 merged2026-07-29 and published1.3; grpcbox PR121 adopted1.2
  earlier and the published range still excludes1.3. Gproc is introduced by the
  opt-in/test exporter graph, not the none/API/SDK dependency graph.

No compatible official update makes this graph strictly clean. Leave the lock,
dependency sources, strict checker and red results intact. This is a documented
upstream follow-up, not a functional test failure or a publication waiver. The
[guide](../../development/known-limits.md) records official links and specific
adoption checks. No upstream issue/comment/PR was posted.

Private evidence: `.exagent-local/known-limits20261003/`, including each wave's
source/admission/admissions/cases/receipt, source identity, compiler-log hashes,
official package metadata and merged-fix records. Final root documentation/TAR
verification is recorded below. No new FULL, SQL, cloud, load or model-switch work.

## Final documentation and artifact verification

Format and strict root compilation pass. After clarifying the dated complex
receipt, strict ExDoc and links pass:119 HTML pages/5320 targets,117 Markdown
pages/872 targets and117 EPUB pages/2941 targets, zero missing local targets.
Package build and acceptance-isolation checks pass; fake host remains unchanged.

Final nominal1.3.0 TAR SHA256:
`1669807e28007c99691d3f760d6a7a5713e82a256cc23094ff9c9ff24dd0fddc`.
All170 files match the checkout. Compared with the prior aligned TAR
`4eff85d9dd412751a257b434e3c70d0c5ebf9d9503d7dc2cb8b8d0ad0af8164f`,
the only added file is the published known-limits guide; no file removed.
All91 library source files are byte-identical. Mix AST is identical excluding
docs/0; metadata is identical excluding the file list. No runtime, requirements,
version, lock, pricing, privacy, guard or accounting change.

The first metadata helper compared a binary key to a charlist, so its comparison
failed. Fixing the inspection key passes; the original red helper is retained.
Final logs/source manifest are in documentation-gates-02.json and
final-package-source.json; earlier successful compile/format remain applicable.
The unchanged runtime reuses its dated FULL/focal/cloud/SQL/consumer receipts;
this documentary TAR does not acquire a new full matrix qualification.
