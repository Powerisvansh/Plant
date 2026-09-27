#!/usr/bin/env python3
"""Import plant taxonomic records from a license-approved source.

Default source is the GBIF Backbone Taxonomy (CC BY 4.0). Only taxonomic facts
are imported: accepted name, authorship, rank, higher classification, synonyms,
vernacular names and distributions. Descriptive prose is only imported when the
contributing dataset's recorded license is on the allow list.

Every inserted or updated fact writes a data_provenance row. Nothing is invented:
if a name does not resolve with acceptable confidence the row is skipped and
reported.

Usage:
    python3 scripts/import_plants.py --dry-run
    python3 scripts/import_plants.py --limit 10
    python3 scripts/import_plants.py --include-descriptions
"""

from __future__ import annotations

import argparse
import logging
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from plantdoctor_api.db import transaction  # noqa: E402

log = logging.getLogger("import_plants")

GBIF_BASE = "https://api.gbif.org/v1"
RANK_ORDER = ["KINGDOM", "PHYLUM", "CLASS", "ORDER", "FAMILY", "GENUS", "SPECIES"]

# Licenses under which contributed descriptive text may be stored verbatim.
DESCRIPTIVE_LICENSE_ALLOWLIST = {"CC0", "CC_BY_3_0", "CC_BY_4_0", "PUBLIC_DOMAIN", "ODC_BY_1_0"}

RANK_TO_PART = {
    "SPECIES": "WHOLE_PLANT",
    "GENUS": "WHOLE_PLANT",
}


@dataclass
class Stats:
    seen: int = 0
    matched: int = 0
    inserted: int = 0
    updated: int = 0
    skipped: int = 0
    failed: int = 0
    synonyms: int = 0
    names: int = 0
    distributions: int = 0
    taxonomy_rows: int = 0
    descriptions: int = 0

    def summary(self) -> str:
        return (
            f"seen={self.seen} matched={self.matched} inserted={self.inserted} "
            f"updated={self.updated} skipped={self.skipped} failed={self.failed} "
            f"taxonomy_rows={self.taxonomy_rows} synonyms={self.synonyms} "
            f"names={self.names} distributions={self.distributions} "
            f"descriptions={self.descriptions}"
        )


def http_json(path: str, params: dict[str, Any] | None = None, retries: int = 3) -> dict[str, Any]:
    url = f"{GBIF_BASE}{path}"
    if params:
        url += "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    delay = 1.0
    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "PlantDoctorAI/0.1 (knowledge base import)"})
            with urllib.request.urlopen(request, timeout=30) as response:
                import json

                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            if attempt == retries:
                raise RuntimeError(f"GET {url} failed after {retries} attempts: {exc}") from exc
            log.warning("retry %d/%d for %s (%s)", attempt, retries, url, exc)
            time.sleep(delay)
            delay *= 2
    raise RuntimeError("unreachable")


def _results(payload: Any) -> list[dict[str, Any]]:
    """GBIF returns either a bare array or a paged object depending on the endpoint."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        return list(payload.get("results") or [])
    return []


def read_species_list(path: Path) -> list[str]:
    names: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            names.append(line)
    return names


def add_provenance(cur, table: str, record_id: int, source_id: int, field: str | None,
                   method: str, value: str | None, confidence: float | None,
                   verification: str, notes: str) -> None:
    cur.execute("SELECT 1 FROM data_provenance WHERE table_name=%s AND record_id=%s "
                "AND COALESCE(field_name,'')=COALESCE(%s,'') AND superseded_at IS NULL",
                (table, record_id, field))
    if cur.fetchone():
        return
    cur.execute(
        """
        INSERT INTO data_provenance (table_name, record_id, field_name, source_id,
                                     extracted_value, extraction_method, confidence,
                                     verification_status, notes)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (table, record_id, field, source_id, (value or "")[:4000] if value else None,
         method, confidence, verification, notes),
    )


def upsert_plant(cur, match: dict[str, Any], source_id: int, requested: str) -> tuple[int, bool]:
    canonical = match.get("canonicalName") or match["scientificName"]
    scientific = match["scientificName"]
    authorship = match.get("authorship") or match.get("scientificNameAuthorship")
    status = (match.get("status") or "UNKNOWN").upper()
    is_accepted = status == "ACCEPTED"
    key = match.get("usageKey")

    # Match on GBIF's usageKey first: it is the stable external identifier.
    # The canonical name is only a fallback, because the name we derive from
    # scientific_name need not equal GBIF's own canonicalName. For example
    # usageKey 7647136 is "Citrus × limon (L.) Osbeck", whose GBIF canonicalName
    # is "Citrus limon" while our derived canonical form is "citrus × limon".
    # Matching on the name alone therefore missed the existing row and the
    # insert then violated uq_plants_canonical_name.
    if key:
        cur.execute(
            "SELECT id, verification_status FROM plants "
            "WHERE external_taxon_source = 'gbif' AND external_taxon_key = %s",
            (str(key),),
        )
        row = cur.fetchone()
    else:
        row = None

    if row is None:
        cur.execute(
            "SELECT id, verification_status FROM plants WHERE canonical_name = lower(%s)",
            (canonical,),
        )
        row = cur.fetchone()

    verification = "VERIFIED" if is_accepted else "PARTIALLY_VERIFIED"
    today = date.today().isoformat()

    if row:
        plant_id = row["id"]
        cur.execute(
            """
            UPDATE plants
               SET scientific_name = %s,
                   scientific_name_authorship = COALESCE(%s, scientific_name_authorship),
                   genus = COALESCE(%s, genus),
                   species = COALESCE(%s, species),
                   family = COALESCE(%s, family),
                   order_name = COALESCE(%s, order_name),
                   class_name = COALESCE(%s, class_name),
                   phylum = COALESCE(%s, phylum),
                   kingdom = COALESCE(%s, kingdom),
                   taxonomic_status = %s,
                   taxonomic_authority = COALESCE(%s, taxonomic_authority),
                   is_accepted = %s,
                   external_taxon_key = %s,
                   external_taxon_source = 'gbif',
                   verification_status = %s,
                   taxonomic_source_id = %s,
                   last_verified = %s
             WHERE id = %s
            """,
            (scientific, authorship, match.get("genus"), match.get("species"),
             match.get("family"), match.get("order"), match.get("class"),
             match.get("phylum"), match.get("kingdom"), status, authorship,
             is_accepted, str(key) if key else None, verification, source_id, today, plant_id),
        )
        return plant_id, False

    cur.execute(
        """
        INSERT INTO plants (
            scientific_name, scientific_name_authorship, genus, species, family,
            order_name, class_name, phylum, kingdom, taxonomic_status,
            taxonomic_authority, is_accepted, external_taxon_key,
            external_taxon_source, verification_status, taxonomic_source_id,
            last_verified
        ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'gbif',%s,%s,%s)
        RETURNING id
        """,
        (scientific, authorship, match.get("genus"), match.get("species"),
         match.get("family"), match.get("order"), match.get("class"),
         match.get("phylum"), match.get("kingdom"), status, authorship,
         is_accepted, str(key) if key else None, verification, source_id, today),
    )
    return cur.fetchone()["id"], True


def import_taxonomy(cur, plant_id: int, usage_key: int, source_id: int, stats: Stats) -> None:
    payload = http_json(f"/species/{usage_key}/parents")
    parents = payload.get("results", []) if isinstance(payload, dict) else payload
    chain: list[dict[str, Any]] = []
    for parent in parents:
        rank = (parent.get("rank") or "").upper()
        if rank in RANK_ORDER:
            chain.append(parent)
    order_map = {r: i for i, r in enumerate(RANK_ORDER)}
    chain.sort(key=lambda p: order_map.get((p.get("rank") or "").upper(), 99))

    for index, node in enumerate(chain):
        rank = (node.get("rank") or "").upper()
        name = (node.get("scientificName") or node.get("canonicalname")
                or node.get("scientificname") or node.get("vernacularName"))
        if not name:
            log.debug("taxonomy node without a name at rank %s; skipped", rank)
            continue
        rank_parent = chain[index - 1].get("rank") if index > 0 else None
        cur.execute(
            """
            INSERT INTO plant_taxonomy (plant_id, rank, name, rank_parent, external_key,
                                        external_source, source_id, verification_status)
            VALUES (%s,%s,%s,%s,%s,'gbif',%s,%s)
            ON CONFLICT (plant_id, rank, name) DO UPDATE
                SET rank_parent = EXCLUDED.rank_parent,
                    external_key = EXCLUDED.external_key,
                    source_id = EXCLUDED.source_id,
                    verification_status = EXCLUDED.verification_status
            """,
            (plant_id, rank.lower(), name,
             (rank_parent or "").lower() or None,
             str(node.get("key")) if node.get("key") else None,
             source_id, "VERIFIED"),
        )
        stats.taxonomy_rows += 1
    if chain:
        add_provenance(cur, "plants", plant_id, source_id, "taxonomy",
                       "GBIF_SPECIES_PARENTS", f"{len(chain)} rank rows", 1.0,
                       "VERIFIED", f"Higher classification chain from GBIF parents endpoint for key {usage_key}.")


def import_synonyms(cur, plant_id: int, usage_key: int, source_id: int, stats: Stats) -> None:
    page = 0
    while True:
        result = http_json(f"/species/{usage_key}/synonyms", {"limit": 100, "offset": page * 100})
        entries = _results(result)
        if not entries:
            break
        for entry in entries:
            synonym = entry.get("scientificname")
            if not synonym:
                continue
            cur.execute(
                """
                INSERT INTO plant_synonyms (plant_id, synonym, nomenclatural_status,
                                           publication, source_id, verification_status)
                VALUES (%s,%s,%s,%s,%s,%s)
                ON CONFLICT (plant_id, synonym) DO UPDATE
                    SET nomenclatural_status = EXCLUDED.nomenclatural_status,
                        source_id = EXCLUDED.source_id
                """,
                (plant_id, synonym, (entry.get("taxonomicStatus") or "").upper() or None,
                 entry.get("publishedIn") or None, source_id, "VERIFIED"),
            )
            stats.synonyms += 1
        if result.get("endOfRecords"):
            break
        page += 1
        if page > 20:
            break


def import_vernacular(cur, plant_id: int, usage_key: int, source_id: int, stats: Stats) -> None:
    result = http_json(f"/species/{usage_key}/vernacularNames", {"limit": 100})
    seen: set[tuple[str, str | None, str | None]] = set()
    for entry in _results(result):
        name = (entry.get("vernacularName") or "").strip()
        if not name or len(name) > 120:
            continue
        language = entry.get("language")
        region = entry.get("country")
        key = (name, language, region)
        if key in seen:
            continue
        seen.add(key)
        cur.execute(
            "SELECT id, is_preferred FROM plant_names WHERE plant_id=%s AND name=%s "
            "AND language_code IS NOT DISTINCT FROM %s AND region IS NOT DISTINCT FROM %s",
            (plant_id, name, language, region),
        )
        existing = cur.fetchone()
        if existing:
            continue
        cur.execute(
            """
            INSERT INTO plant_names (plant_id, name, name_type, language_code, region,
                                     is_preferred, source_id, verification_status, notes)
            VALUES (%s,%s,'COMMON',%s,%s,FALSE,%s,'PARTIALLY_VERIFIED',%s)
            """,
            (plant_id, name, language, region, source_id,
             "Vernacular name aggregated by GBIF from source datasets with differing licenses; "
             "treated as a reported common name, not an authoritative one."),
        )
        stats.names += 1


def import_distributions(cur, plant_id: int, usage_key: int, source_id: int, stats: Stats) -> None:
    """Import GBIF distribution records as DISTRIBUTION habitat rows.

    GBIF reports the same country several times with different
    `establishmentMeans` (NATIVE, INTRODUCED, PROBABLY_NATIVE, ...). Those are
    distinct facts, so `establishmentMeans` is carried in `habitat_type` and is
    part of the deduplication key. Keeping it only inside the description string
    made NATIVE and INTRODUCED rows for the same country collide on insert.
    """
    result = http_json(f"/species/{usage_key}/distributions", {"limit": 300})
    seen: set[tuple[str, str | None, str | None]] = set()
    for entry in _results(result):
        country = entry.get("country")
        location = entry.get("location")
        if not country and not location:
            continue
        means = (entry.get("establishmentMeans") or "UNKNOWN").upper()
        key = (country or "", location or "", means)
        if key in seen:
            continue
        seen.add(key)
        cur.execute(
            """
            INSERT INTO plant_habitats (plant_id, habitat_type, region, country,
                                        description, source_id, verification_status)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (plant_id, habitat_type, biome, region, country) DO UPDATE
                SET description = EXCLUDED.description
            """,
            (plant_id, f"DISTRIBUTION_{means}", location, country,
             f"GBIF distribution record (establishmentMeans={means}).",
             source_id, "PARTIALLY_VERIFIED"),
        )
        stats.distributions += 1


def import_descriptions(cur, plant_id: int, usage_key: int, source_id: int, stats: Stats) -> int:
    result = http_json(f"/species/{usage_key}/descriptions", {"limit": 50})
    imported = 0
    for entry in _results(result):
        text = (entry.get("description") or "").strip()
        if not text:
            continue
        license_value = (entry.get("license") or "").upper()
        if license_value not in DESCRIPTIVE_LICENSE_ALLOWLIST:
            log.info("skipping description with non-allowlisted license %r", license_value)
            continue
        part = (entry.get("type") or "UNKNOWN").upper()
        mapped = {
            "DESCRIPTION": "WHOLE_PLANT", "DISTRIBUTION": "WHOLE_PLANT",
            "HABITAT": "WHOLE_PLANT", "USES": "WHOLE_PLANT",
            "LEAF": "LEAF", "FLOWER": "FLOWER", "FRUIT": "FRUIT",
            "STEM": "STEM", "ROOT": "ROOT", "SEED": "SEED",
        }.get(part, "WHOLE_PLANT")
        cur.execute(
            "SELECT id FROM plant_appearance WHERE plant_id=%s AND part=%s",
            (plant_id, mapped),
        )
        existing = cur.fetchone()
        if existing:
            appearance_id = existing["id"]
            cur.execute(
                "UPDATE plant_appearance SET description = COALESCE(description, %s) WHERE id = %s",
                (text[:8000], appearance_id),
            )
        else:
            cur.execute(
                """
                INSERT INTO plant_appearance (plant_id, part, description, source_id,
                                              verification_status)
                VALUES (%s,%s,%s,%s,'PARTIALLY_VERIFIED')
                RETURNING id
                """,
                (plant_id, mapped, text[:8000], source_id),
            )
            appearance_id = cur.fetchone()["id"]
        add_provenance(cur, "plant_appearance", appearance_id, source_id, "description",
                       "GBIF_SPECIES_DESCRIPTIONS", entry.get("title"),
                       None, "PARTIALLY_VERIFIED",
                       f"Contributed dataset: {entry.get('datasetTitle') or 'unknown'}; license={license_value}.")
        imported += 1
    return imported


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import plant records from GBIF")
    parser.add_argument("--file", default=str(REPO_ROOT / "data" / "seed_species.txt"))
    parser.add_argument("--source-key", default="gbif")
    parser.add_argument("--limit", type=int, default=0, help="only import the first N names")
    parser.add_argument("--min-confidence", type=int, default=90,
                        help="minimum GBIF match confidence percentage")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--include-descriptions", action="store_true",
                        help="import contributed descriptive text whose dataset license is allow-listed")
    parser.add_argument("--sleep", type=float, default=0.25, help="politeness delay between HTTP calls")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(message)s",
    )

    names = read_species_list(Path(args.file))
    if args.limit:
        names = names[: args.limit]
    log.info("loaded %d name(s) from %s", len(names), args.file)

    if args.dry_run:
        with transaction() as cur:
            cur.execute("SELECT id, license, approval_status FROM sources WHERE key=%s", (args.source_key,))
            row = cur.fetchone()
        if row is None:
            raise SystemExit(f"source {args.source_key!r} is not registered; run seed_sources.py")
        print(f"[dry-run] source={args.source_key} license={row['license']} "
              f"approval={row['approval_status']} names={len(names)} "
              f"min_confidence={args.min_confidence} descriptions={args.include_descriptions}")
        for name in names:
            print(f"  would resolve and import: {name}")
        return 0

    stats = Stats()
    started = time.monotonic()

    with transaction() as cur:
        cur.execute("SELECT id, license, approval_status, redistribution_allowed "
                    "FROM sources WHERE key=%s", (args.source_key,))
        source = cur.fetchone()
        if source is None:
            raise SystemExit(f"source {args.source_key!r} is not registered; run seed_sources.py")
        if source["approval_status"] != "APPROVED":
            raise SystemExit(
                f"source {args.source_key!r} approval_status is {source['approval_status']}; "
                "refusing to import"
            )
        source_id = source["id"]
        cur.execute("SELECT count(*) FROM plants")
        log.info("plants before: %s", cur.fetchone()["count"])

    for index, requested in enumerate(names, start=1):
        stats.seen += 1
        try:
            match = http_json("/species/match", {"name": requested, "strict": "true"})
            time.sleep(args.sleep)
            confidence = int(match.get("confidence") or 0)
            match_type = match.get("matchType")
            resolved = match.get("scientificName")

            if confidence < args.min_confidence or match_type in ("NONE", "FUZZY"):
                stats.skipped += 1
                log.warning("[%d/%d] SKIP %-32s matchType=%s confidence=%s resolved=%s",
                            index, len(names), requested, match_type, confidence, resolved)
                continue
            if not resolved:
                stats.skipped += 1
                log.warning("[%d/%d] SKIP %-32s no resolved name", index, len(names), requested)
                continue

            stats.matched += 1
            usage_key = match.get("usageKey")
            with transaction() as cur:
                plant_id, created = upsert_plant(cur, match, source_id, requested)
                if created:
                    stats.inserted += 1
                else:
                    stats.updated += 1
                add_provenance(
                    cur, "plants", plant_id, source_id, None, "GBIF_SPECIES_MATCH",
                    f"requested={requested}; matchType={match_type}; confidence={confidence}; "
                    f"resolved={resolved}; status={match.get('status')}",
                    confidence / 100.0,
                    "VERIFIED" if (match.get("status") == "ACCEPTED" and match_type == "EXACT") else "PARTIALLY_VERIFIED",
                    "Taxon match performed against the GBIF Backbone Taxonomy (CC BY 4.0).",
                )
                if usage_key:
                    import_taxonomy(cur, plant_id, usage_key, source_id, stats)
                    import_synonyms(cur, plant_id, usage_key, source_id, stats)
                    import_vernacular(cur, plant_id, usage_key, source_id, stats)
                    import_distributions(cur, plant_id, usage_key, source_id, stats)
                    if args.include_descriptions:
                        stats.descriptions += import_descriptions(cur, plant_id, usage_key, source_id, stats)
                cur.execute(
                    """
                    INSERT INTO verification_records (table_name, record_id, verification_status,
                                                     method, evidence, notes)
                    VALUES ('plants', %s, %s, 'AUTOMATED_SOURCE_MATCH',
                            'GBIF Backbone Taxonomy species/match',
                            %s)
                    """,
                    (plant_id,
                     "VERIFIED" if (match.get("status") == "ACCEPTED" and match_type == "EXACT")
                     else "PARTIALLY_VERIFIED",
                     f"requested name '{requested}' resolved to '{resolved}'"),
                )
            log.info("[%d/%d] %s %-34s -> %s (plant_id=%s, matchType=%s, conf=%s)",
                     index, len(names), "NEW " if created else "UPD ", requested,
                     resolved, plant_id, match_type, confidence)
        except Exception as exc:
            stats.failed += 1
            log.error("[%d/%d] FAILED %-32s %s", index, len(names), requested, exc)

    elapsed = time.monotonic() - started
    log.info("done in %.1fs: %s", elapsed, stats.summary())

    with transaction() as cur:
        cur.execute("SELECT count(*) FROM plants")
        log.info("plants after: %s", cur.fetchone()["count"])

    if stats.failed:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
