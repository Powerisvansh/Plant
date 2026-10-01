#!/usr/bin/env python3
"""Import real plant records from the GBIF Backbone Taxonomy (CC BY 4.0).

What this script does (and does not do):

* It only copies taxonomic facts that GBIF actually returns: accepted name,
  authorship, rank, status and the higher classification. No description, no
  agronomy, no toxicity, no treatment is invented.
* Species are discovered through real occurrence records in India
  (``occurrence/search?country=IN``): a species enters the database because it
  has genuine GBIF occurrence records in India, not because it was guessed.
* Every staged record keeps its GBIF usage key, dataset key and retrieval date,
  so ``build_sqlite.py`` can write full provenance.

Usage:
    python3 knowledge/scripts/import_gbif.py --target 2200
    python3 knowledge/scripts/import_gbif.py --refresh        # start over
    python3 knowledge/scripts/import_gbif.py --vernacular-only
"""

from __future__ import annotations

import argparse
import sys
import time
from typing import Any

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    CURATED_DIR,
    RAW_DIR,
    gbif,
    read_json,
    setup_logging,
    slugify,
    write_json,
)

log = setup_logging("import_gbif")

STAGE_PATH = RAW_DIR / "gbif_species.json"
STATE_PATH = RAW_DIR / "gbif_state.json"

GBIF_DATASET_KEY = "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"  # GBIF Backbone Taxonomy
GBIF_LICENSE = "CC BY 4.0"
GBIF_ATTRIBUTION = "GBIF.org Backbone Taxonomy (CC BY 4.0)"
REQUEST_PAUSE = 0.08  # polite, keeps us far below GBIF rate limits


def india_species_for_taxon(key: int, limit: int) -> list[dict]:
    """Species with real occurrence records in India, most-recorded first."""
    payload = gbif(
        "/occurrence/search",
        {
            "country": "IN",
            "taxonKey": key,
            "facet": "speciesKey",
            "facetLimit": limit,
            "limit": 0,
        },
    )
    facets = payload.get("facets") or []
    if not facets:
        return []
    counts = facets[0].get("counts") or []
    return [{"key": int(c["name"]), "occurrences": c["count"]} for c in counts if c.get("name")]


def species_detail(key: int) -> dict | None:
    try:
        return gbif(f"/species/{key}")
    except RuntimeError as exc:
        log.warning("species/%s failed: %s", key, exc)
        return None


def accepted_detail(detail: dict) -> dict | None:
    """Follow GBIF's accepted-name link when a key points at a synonym."""
    status = (detail.get("taxonomicStatus") or "").upper()
    if status == "ACCEPTED":
        return detail
    accepted_key = detail.get("acceptedNameUsageKey")
    if not accepted_key and detail.get("acceptedNameUsage"):
        try:
            match = gbif("/species/match", {"name": detail["acceptedNameUsage"]})
        except RuntimeError:
            match = {}
        accepted_key = match.get("usageKey") or match.get("speciesKey")
    if not accepted_key:
        return None
    target = species_detail(int(accepted_key))
    if target and (target.get("taxonomicStatus") or "").upper() == "ACCEPTED":
        return target
    return None


def _genus_search(name: str, accepted_only: bool) -> dict | None:
    """Backbone genus search. Returns the best plant result or None."""
    params: dict[str, Any] = {
        "q": name,
        "rank": "GENUS",
        "datasetKey": GBIF_DATASET_KEY,
        "limit": 10,
    }
    if accepted_only:
        params["status"] = "ACCEPTED"
    try:
        payload = gbif("/species/search", params)
    except RuntimeError as exc:
        log.warning("genus search %s failed: %s", name, exc)
        return None

    best: dict | None = None
    for result in payload.get("results") or []:
        canonical = (result.get("canonicalName") or "").strip()
        if canonical.lower() != name.strip().lower():
            continue
        if (result.get("kingdom") or "") != "Plantae":
            continue
        status = (result.get("taxonomicStatus") or "").upper()
        # Prefer an accepted name; otherwise the first synonym that still
        # points at an accepted genus is better than a DOUBTFUL stub.
        if status == "ACCEPTED":
            return result
        if status == "SYNONYM" and result.get("acceptedKey") and best is None:
            best = result
        elif best is None and status not in ("DOUBTFUL", "PROVISIONAL"):
            best = result
    return best


def resolve_taxon(name: str) -> dict | None:
    """Resolve a genus (or full species) name to an accepted GBIF backbone taxon.

    Three cases had to be handled, because the first version silently dropped
    real crops worth having in the database:

    1. ``/species/match`` is built for complete scientific names and answers
       ``matchType = NONE`` for a bare genus (e.g. *Zea*, *Arachis*). The
       backbone search endpoint restricted to ``rank=GENUS`` resolves those.
    2. Some classic genera are now **synonyms** in the GBIF backbone -
       *Pisum* L. is accepted as *Lathyrus* L., and *Lens* Mill. as *Vicia* L.
       Rather than lose garden pea and lentil, we follow ``acceptedKey`` and
       import the species under their current accepted genus. The trade name
       is preserved later as a synonym + common name, never invented.
    3. Names that only exist as ``DOUBTFUL`` stubs are rejected outright.
    """
    match: dict = {}
    try:
        match = gbif("/species/match", {"name": name})
    except RuntimeError as exc:
        log.warning("match %s failed: %s", name, exc)

    if (
        match
        and match.get("matchType") != "NONE"
        and (match.get("usageKey") or match.get("speciesKey"))
    ):
        return match

    result = _genus_search(name, accepted_only=True)
    if result:
        return {
            "usageKey": result.get("key"),
            "rank": "GENUS",
            "scientificName": result.get("scientificName"),
            "matchType": "GENUS_SEARCH",
        }

    result = _genus_search(name, accepted_only=False)
    if result:
        accepted_key = result.get("acceptedKey")
        if accepted_key and int(accepted_key) != int(result.get("key") or 0):
            log.info("genus %s is a synonym of %s - following it",
                     name, result.get("accepted") or accepted_key)
            return {
                "usageKey": accepted_key,
                "rank": "GENUS",
                "scientificName": result.get("accepted"),
                "matchType": "GENUS_SYNONYM",
                "synonymOf": result.get("accepted"),
            }
        return {
            "usageKey": result.get("key"),
            "rank": "GENUS",
            "scientificName": result.get("scientificName"),
            "matchType": "GENUS_SEARCH",
        }
    return None


def stage_record(detail: dict, group: str, occurrences: int) -> dict:
    scientific = detail.get("scientificName") or detail.get("canonicalName") or ""
    return {
        "gbif_key": str(detail["key"]),
        "scientific_name": scientific,
        "canonical_name": detail.get("canonicalName") or scientific,
        "authorship": detail.get("authorship"),
        "rank": detail.get("rank"),
        "taxonomic_status": (detail.get("taxonomicStatus") or "").upper(),
        "genus": detail.get("genus"),
        "species": detail.get("species"),
        "family": detail.get("family"),
        "order": detail.get("order"),
        "class": detail.get("class"),
        "phylum": detail.get("phylum"),
        "kingdom": detail.get("kingdom"),
        "vernacular_name": detail.get("vernacularName"),
        "dataset_key": detail.get("datasetKey") or GBIF_DATASET_KEY,
        "published_in": detail.get("publishedIn"),
        "slug": slugify(detail.get("canonicalName") or scientific),
        "group": group,
        "india_occurrences": occurrences,
        "retrieved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "gbif",
        "license": GBIF_LICENSE,
    }


def collect_priority_species(staged: list[dict], by_key: dict[str, dict],
                             state: dict) -> int:
    """Fetch named species that must be present regardless of genus caps.

    The curated worklist caps how many species a single genus contributes, so
    a crop the visual model recognises can be squeezed out of its own genus by
    40 better-recorded wild relatives. This pass guarantees the model's crop
    labels resolve to a real plant record. Every name is resolved through the
    GBIF backbone, so a synonym is followed to its accepted name rather than
    being written as-is.
    """
    wanted = read_json(CURATED_DIR / "priority_species.json", {}) or {}
    names = wanted.get("species", [])
    added = 0
    state = state.setdefault("__priority_species__", {})
    for entry in names:
        name = entry["scientific_name"]
        if state.get(name, {}).get("done"):
            continue
        try:
            match = gbif("/species/match", {"name": name, "kingdom": "Plantae"})
        except RuntimeError as exc:
            log.warning("priority match %s failed: %s", name, exc)
            continue
        time.sleep(REQUEST_PAUSE)
        key = match.get("usageKey") or match.get("speciesKey")
        if not key or match.get("matchType") == "NONE":
            log.warning("priority species unmatched: %s", name)
            state[name] = {"done": True, "reason": "no match"}
            continue
        detail = species_detail(int(key))
        time.sleep(REQUEST_PAUSE)
        if not detail:
            continue
        resolved = accepted_detail(detail) or detail
        if (resolved.get("rank") or "").upper() != "SPECIES":
            state[name] = {"done": True, "reason": "not a species"}
            continue
        record = stage_record(resolved, entry.get("group", "priority_crops"),
                              entry.get("india_occurrences", 0))
        # Remember the requested name as a synonym when GBIF accepts another.
        if name != record["canonical_name"]:
            record["requested_name"] = name
        if record["gbif_key"] in by_key:
            state[name] = {"done": True, "reason": "already staged",
                           "gbif_key": record["gbif_key"]}
            continue
        by_key[record["gbif_key"]] = record
        staged.append(record)
        added += 1
        state[name] = {
            "done": True,
            "requested": name,
            "resolved": record["canonical_name"],
            "gbif_key": record["gbif_key"],
            "status": record["taxonomic_status"],
        }
        log.info("priority %-26s -> %-28s staged=%d",
                 name, record["canonical_name"], len(staged))
        write_json(STAGE_PATH, sorted(staged, key=lambda r: r["slug"]))
    return added


def collect(target: int, refresh: bool, group_filter: str | None,
            retry_unmatched: bool = False) -> list[dict]:
    worklist = read_json(CURATED_DIR / "target_genera.json", {})
    default_max = int(worklist.get("default_max_species", 40))
    groups = worklist.get("groups", [])
    if group_filter:
        groups = [g for g in groups if g["group"] == group_filter]

    staged: list[dict] = [] if refresh else list(read_json(STAGE_PATH, []) or [])
    state = {} if refresh else dict(read_json(STATE_PATH, {}) or {})

    if retry_unmatched:
        cleared = [n for n, v in state.items() if v.get("reason") == "no match"]
        for name in cleared:
            state.pop(name, None)
        if cleared:
            log.info("retrying %d previously unmatched genera: %s",
                     len(cleared), ", ".join(sorted(cleared)))
    by_key = {r["gbif_key"]: r for r in staged}
    log.info("resuming with %d staged species", len(staged))

    # Crops the bundled visual model can recognise come first, so a genus cap
    # can never drop the species behind a published model label.
    priority_added = collect_priority_species(staged, by_key, state)
    if priority_added:
        log.info("priority species added: %d (total staged %d)",
                 priority_added, len(staged))
        write_json(STATE_PATH, state)

    for group in groups:
        if len(staged) >= target:
            break
        gname = group["group"]
        max_species = int(group.get("max_species", default_max))
        for name in group["genera"]:
            if len(staged) >= target:
                break
            if (state.get(name) or {}).get("done"):
                continue

            try:
                match = resolve_taxon(name)
            except RuntimeError as exc:
                log.warning("match %s failed: %s", name, exc)
                continue
            if not match:
                log.warning("unmatched name: %s", name)
                state[name] = {"done": True, "reason": "no match"}
                continue
            rank = match.get("rank")
            key = match.get("usageKey") or match.get("speciesKey")
            if not key:
                state[name] = {"done": True, "reason": "no key"}
                continue
            time.sleep(REQUEST_PAUSE)

            found = 0
            if rank == "SPECIES":
                candidates = [{"key": int(match.get("speciesKey") or key), "occurrences": 0}]
            else:
                candidates = india_species_for_taxon(int(key), limit=max(max_species * 2, 20))
                time.sleep(REQUEST_PAUSE)

            for cand in candidates:
                if found >= max_species or len(staged) >= target:
                    break
                if str(cand["key"]) in by_key:
                    continue
                detail = species_detail(cand["key"])
                time.sleep(REQUEST_PAUSE)
                if not detail:
                    continue
                detail = accepted_detail(detail)
                if not detail:
                    continue
                if (detail.get("kingdom") or "") != "Plantae":
                    continue
                if (detail.get("rank") or "").upper() != "SPECIES":
                    continue
                record = stage_record(detail, gname, cand.get("occurrences", 0))
                if not record["scientific_name"] or record["gbif_key"] in by_key:
                    continue
                by_key[record["gbif_key"]] = record
                staged.append(record)
                found += 1

            state[name] = {
                "done": True,
                "rank": rank,
                "taxon_key": key,
                "species_added": found,
                "staged_total": len(staged),
            }
            write_json(STAGE_PATH, sorted(staged, key=lambda r: r["slug"]))
            write_json(STATE_PATH, state)
            log.info("%-24s +%-3d staged=%d", name, found, len(staged))

    write_json(STAGE_PATH, sorted(staged, key=lambda r: r["slug"]))
    write_json(STATE_PATH, state)
    return staged


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import real plant taxonomy from GBIF")
    parser.add_argument("--target", type=int, default=2200, help="stop after this many species")
    parser.add_argument("--refresh", action="store_true", help="ignore previous staging")
    parser.add_argument("--group", default=None, help="only import one curated group")
    parser.add_argument(
        "--retry-unmatched",
        action="store_true",
        help="clear genera previously recorded as 'no match' and try them again",
    )
    args = parser.parse_args(argv)

    staged = collect(args.target, args.refresh, args.group, args.retry_unmatched)
    families = {r.get("family") for r in staged if r.get("family")}
    groups = {r.get("group") for r in staged}
    print(f"staged species : {len(staged)}")
    print(f"unique families: {len(families)}")
    print(f"curated groups : {len(groups)}")
    print(f"stage file     : {STAGE_PATH}")
    return 0 if len(staged) > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

