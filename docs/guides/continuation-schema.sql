-- Application-owned migration template. Never executed by ExAgent startup.
-- Use the same selected table for snapshots and atomic record envelopes.
-- Existing installations with this schema need no second authoritative table.
-- Configure a bare SQL identifier via {Repo, table: "exagent_snapshots"}; manage
-- schema/search_path and connection permissions in the application's Repo.
CREATE TABLE IF NOT EXISTS "exagent_snapshots" (
  key text PRIMARY KEY,
  data text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- data holds either an existing snapshot or record_version=1 JSON, never both.
-- Atomic command revision, record lifetime ID, execution fence and operation
-- receipts live inside the envelope and change under SELECT ... FOR UPDATE.
-- The application must stop old writers before an explicit format migration.
-- SQL locks/recovery/backup are qualified in the finite PostgreSQL G3 profile.
-- See docs/status.md and docs/development/production-acceptance.md for its limits;
-- this template alone does not qualify another database/deployment combination.
