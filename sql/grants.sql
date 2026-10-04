-- DigitalOcean managed MySQL 8 - least-privilege setup for the Aardvark pipeline.
-- Run as the DO admin user (doadmin) against the managed cluster.
--
-- Topology:
--   wespa      = production schema (served read-only by the API)
--   wespa_dev  = staging schema rebuilt by the pipeline, then promoted to wespa

-- 1. Schemas. Both are pre-created here so the pipeline never needs
--    CREATE/DROP DATABASE privileges.
CREATE DATABASE IF NOT EXISTS wespa     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS wespa_dev CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 2. Build/promote user. Needs full DDL/DML on both schemas so it can rebuild
--    staging and replace the tables in production. No global privileges.
CREATE USER IF NOT EXISTS 'aardvark_build'@'%' IDENTIFIED BY 'CHANGE_ME';
GRANT SELECT, INSERT, UPDATE, DELETE,
      CREATE, DROP, ALTER, INDEX, REFERENCES,
      LOCK TABLES, CREATE TEMPORARY TABLES
  ON wespa.*     TO 'aardvark_build'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE,
      CREATE, DROP, ALTER, INDEX, REFERENCES,
      LOCK TABLES, CREATE TEMPORARY TABLES
  ON wespa_dev.* TO 'aardvark_build'@'%';

-- 3. API/reporting user: read-only on production.
--    (The managed server enforces TLS via require_secure_transport.)
CREATE USER IF NOT EXISTS 'wespa'@'%' IDENTIFIED BY 'CHANGE_ME';
GRANT SELECT ON wespa.* TO 'wespa'@'%';

FLUSH PRIVILEGES;
