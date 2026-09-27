"""CRUD operations and database-level constraint enforcement.

These tests confirm the database refuses bad data on its own, so a faulty
importer cannot quietly write nonsense into the knowledge base.
"""

from __future__ import annotations

import psycopg
import pytest

from conftest import insert_disease, insert_plant, insert_source, insert_symptom
from plantdoctor_api.db import query_all, query_one, query_scalar


def test_create_read_update_delete_plant(db, src):
    with db.connection() as conn:
        with conn.cursor() as cur:
            pid = insert_plant(cur, "Solanum lycopersicum L.", src, "Cultivated tomato.")
        conn.commit()

    row = query_one("SELECT scientific_name, description FROM plants WHERE id = %s", (pid,))
    assert row["scientific_name"] == "Solanum lycopersicum L."

    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE plants SET description = %s WHERE id = %s", ("Updated.", pid))
        conn.commit()
    assert query_one("SELECT description FROM plants WHERE id = %s", (pid,))["description"] == "Updated."

    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE plants SET is_deleted = TRUE WHERE id = %s", (pid,))
        conn.commit()
    assert query_one("SELECT is_deleted FROM plants WHERE id = %s", (pid,))["is_deleted"] is True
    assert query_scalar("SELECT count(*) FROM v_plant_overview WHERE plant_id = %s", (pid,)) == 0


def test_duplicate_plant_scientific_name_rejected(db, src):
    with db.connection() as conn:
        with conn.cursor() as cur:
            insert_plant(cur, "Solanum tuberosum L.", src)
        conn.commit()
    with pytest.raises(psycopg.errors.UniqueViolation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                insert_plant(cur, "Solanum tuberosum L.", src)
            conn.commit()


def test_duplicate_source_key_rejected(db):
    with db.connection() as conn:
        with conn.cursor() as cur:
            insert_source(cur, "powo", "Plants of the World Online")
        conn.commit()
    with pytest.raises(psycopg.errors.UniqueViolation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                insert_source(cur, "powo", "Duplicate")
            conn.commit()


def test_invalid_verification_status_rejected(db, src):
    with pytest.raises(psycopg.errors.InvalidTextRepresentation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO plants (scientific_name, verification_status) "
                    "VALUES (%s, %s)",
                    ("Fakeus plantus", "TOTALLY_MADE_UP"),
                )
            conn.commit()


def test_negative_height_rejected_by_check_constraint(db, src):
    with pytest.raises(psycopg.errors.CheckViolation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO plants (scientific_name, mature_height_min_m) VALUES (%s, %s)",
                    ("Negativa plantus", -5),
                )
            conn.commit()


def test_inverted_height_range_rejected(db, src):
    with pytest.raises(psycopg.errors.CheckViolation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO plants (scientific_name, mature_height_min_m, mature_height_max_m) "
                    "VALUES (%s, %s, %s)",
                    ("Inversa plantus", 10, 2),
                )
            conn.commit()


def test_foreign_key_to_unknown_plant_rejected(db, src):
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO plant_names (plant_id, name) VALUES (%s, %s)",
                    (999_999_999, "Ghost plant"),
                )
            conn.commit()


def test_null_scientific_name_rejected(db):
    with pytest.raises(psycopg.errors.NotNullViolation):
        with db.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO plants (scientific_name) VALUES (NULL)")
            conn.commit()


def test_updated_at_trigger_maintained(db, src):
    with db.connection() as conn:
        with conn.cursor() as cur:
            pid = insert_plant(cur, "Triggersia plantus", src)
            cur.execute("SELECT updated_at FROM plants WHERE id = %s", (pid,))
            before = cur.fetchone()["updated_at"]
            cur.execute("UPDATE plants SET description = 'x' WHERE id = %s", (pid,))
            cur.execute("SELECT updated_at FROM plants WHERE id = %s", (pid,))
            after = cur.fetchone()["updated_at"]
        conn.commit()
    assert after >= before


def test_canonical_name_is_derived_not_supplied(db, src):
    """canonical_name must be computed by the database, not typed in by hand."""
    with db.connection() as conn:
        with conn.cursor() as cur:
            pid = insert_plant(cur, "Ocimum basilicum L.", src)
        conn.commit()
    row = query_one("SELECT canonical_name, scientific_name FROM plants WHERE id = %s", (pid,))
    assert row["canonical_name"] == "ocimum basilicum"
    assert row["canonical_name"] != row["scientific_name"]


def test_bare_taxon_name_strips_author_citation():
    assert query_scalar("SELECT fn_bare_taxon_name(%s)", ("Solanum lycopersicum L.",)) == "solanum lycopersicum"
    assert query_scalar("SELECT fn_bare_taxon_name(%s)", ("Ocimum basilicum",)) == "ocimum basilicum"


def test_duplicate_detection_via_merge_helper_exists(db, src):
    """fn_merge_duplicate_plants must exist and reject a merge into itself."""
    assert query_scalar("SELECT to_regprocedure('fn_merge_duplicate_plants(bigint,bigint)')") is not None
    with db.connection() as conn:
        with conn.cursor() as cur:
            pid = insert_plant(cur, "Mergeus plantus", src)
        conn.commit()
    with pytest.raises(Exception):
        query_scalar("SELECT fn_merge_duplicate_plants(%s, %s)", (pid, pid))
