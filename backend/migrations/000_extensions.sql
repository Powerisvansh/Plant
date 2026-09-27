-- 000_extensions.sql
-- Required extensions, created in dependency order so that a fresh database can
-- be built from scratch by running the migrations alone.
--
-- These were previously created by hand on the live database, which meant
-- `CREATE INDEX ... gin_trgm_ops` in 009_search.sql failed on any new database
-- ("operator class gin_trgm_ops does not exist for access method gin").
--
--   pg_trgm   trigram indexes for fuzzy name search (009)
--   btree_gin multicolumn GIN indexes that mix equality and full-text (004, 009)
--   pgcrypto  digest()/gen_random_uuid() for content hashing (002, 008)
--
-- All three are trusted extensions, so the non-superuser `plantdoctor` role can
-- install them in a database it owns.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
