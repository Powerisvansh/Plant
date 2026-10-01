#!/usr/bin/env python3
"""Import an explicit list of crop and priority species from GBIF (CC BY 4.0).

Why this script exists
----------------------
``import_gbif.py`` discovers species by faceting *occurrence records in India*.
That produces a good sample of Indian wild and medicinal flora, but it does not
guarantee that the **cultivated crop species the bundled image model can
actually recognise** are present. Measured on the current build: the model
classifies 14 crops, and the knowledge base contained **none** of them - no
``Solanum lycopersicum``, no ``Malus domestica``, no ``Zea mays``. The model
would have said "Tomato" and the app would have had no tomato record.

So this script resolves a named list through the GBIF species API and merges the
results into the same staging file the main importer writes, keyed by GBIF usage
key. ``build_sqlite.py`` then needs no change.

What it does
------------
* resolves each requested name with ``/species/match`` (official API, not
  scraping), then reads ``/species/{key}`` and ``/species/{key}/parents``
* copies only what GBIF returns: accepted name, authorship, rank, status,
  publishedIn, and the kingdom->genus hierarchy
* fetches an English vernacular name where one exists
* records the GBIF usage key, dataset key, licence and retrieval date, so the
  build writes full provenance
* records the *matched* accepted name, which is how a synonym such as
  ``Sansevieria trifasciata`` ends up stored under its current accepted name

What it never does
------------------
* invent a name, a description, agronomy, toxicity or a treatment
* fall back to a hand-written record when GBIF has no match - an unmatched name
  is reported and skipped
* overwrite an existing record

Usage:
    python3 knowledge/scripts/import_crop_species.py
    python3 knowledge/scripts/import_crop_species.py --dry-run
    python3 knowledge/scripts/import_crop_species.py --only tomato,maize
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    RAW_DIR,
    gbif,
    read_json,
    setup_logging,
    slugify,
    utc_now,
    write_json,
)

log = setup_logging("import_crop_species")

STAGE_PATH = RAW_DIR / "gbif_species.json"
GBIF_DATASET_KEY = "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"
GBIF_LICENSE = "CC BY 4.0"
REQUEST_PAUSE = 0.08

# name -> (group, the model classes that need it)
MODEL_CROPS: dict[str, tuple[str, list[str]]] = {
    "Malus domestica": ("fruits", ["Apple"]),
    "Vaccinium corymbosum": ("fruits", ["Blueberry"]),
    "Prunus avium": ("fruits", ["Cherry"]),
    "Prunus cerasifera": ("fruits", ["Cherry"]),
    "Zea mays": ("agriculture", ["Corn"]),
    "Vitis vinifera": ("fruits", ["Grape"]),
    "Citrus sinensis": ("fruits", ["Orange"]),
    "Prunus persica": ("fruits", ["Peach"]),
    "Capsicum annuum": ("vegetables", ["Pepper, bell"]),
    "Solanum tuberosum": ("vegetables", ["Potato"]),
    "Rubus idaeus": ("fruits", ["Raspberry"]),
    "Glycine max": ("agriculture", ["Soybean"]),
    "Cucurbita pepo": ("vegetables", ["Squash"]),
    "Cucurbita maxima": ("vegetables", ["Squash"]),
    "Fragaria ananassa": ("fruits", ["Strawberry"]),
    "Solanum lycopersicum": ("vegetables", ["Tomato"]),
}

# Priority Indian agriculture, horticulture, medicinal and ornamental species.
# Grouped so the app can offer a browsable, useful catalogue rather than a
# random sample of wild flora.
PRIORITY_GROUPS: dict[str, list[str]] = {
    "cereals": [
        "Oryza sativa", "Triticum aestivum", "Hordeum vulgare", "Avena sativa",
        "Sorghum bicolor", "Pennisetum glaucum", "Eleusine coracana",
        "Setaria italica", "Panicum miliaceum", "Zea mays", "Secale cereale",
        "Triticum durum", "Oryza glaberrima",
    ],
    "pulses": [
        "Cicer arietinum", "Cajanus cajan", "Lens culinaris", "Vigna radiata",
        "Vigna unguiculata", "Phaseolus vulgaris", "Pisum sativum",
        "Arachis hypogaea", "Vicia faba", "Phaseolus lunatus",
    ],
    "oilseeds_and_fibre": [
        "Brassica juncea", "Brassica rapa", "Brassica napus", "Brassica carinata",
        "Brassica campestris", "Sesamum indicum", "Helianthus annuus",
        "Carthamus tinctorius", "Gossypium hirsutum", "Gossypium herbaceum",
        "Corchorus olitorius", "Corchorus capsularis", "Linum usitatissimum",
    ],
    "sugar_and_starch": [
        "Saccharum officinarum", "Sorghum bicolor", "Manihot esculenta",
        "Colocasia esculenta", "Dioscorea alata", "Ipomoea batatas",
    ],
    "vegetables": [
        "Solanum lycopersicum", "Solanum tuberosum", "Solanum melongena",
        "Capsicum annuum", "Capsicum chinense", "Allium cepa", "Allium sativum",
        "Allium fistulosum", "Brassica oleracea var. capitata",
        "Brassica oleracea var. botrytis", "Brassica oleracea var. italica",
        "Spinacia oleracea", "Abelmoschus esculentus", "Daucus carota",
        "Raphanus sativus", "Cucumis sativus", "Cucumis melo",
        "Citrullus lanatus", "Momordica charantia", "Luffa aegyptiaca",
        "Luffa cylindrica", "Trichosanthes dioica", "Benincasa hispida",
        "Pisum sativum", "Phaseolus vulgaris", "Beta vulgaris",
        "Amaranthus tricolor", "Coriandrum sativum", "Ocimum basilicum",
    ],
    "fruits": [
        "Mangifera indica", "Musa acuminata", "Musa balbisiana",
        "Psidium guajava", "Carica papaya", "Punica granatum", "Vitis vinifera",
        "Citrus sinensis", "Citrus aurantifolia", "Citrus medica",
        "Cocos nucifera", "Artocarpus heterophyllus", "Aegle marmelos",
        "Tamarindus indica", "Syzygium cumini", "Syzygium cum",
        "Litchi chinensis", "Mangifera indica", "Ananas comosus",
        "Fragaria ananassa", "Rubus idaeus", "Malus domestica", "Prunus persica",
        "Prunus avium", "Prunus cerasifera", "Vaccinium corymbosum",
        "Ficus carica", "Ziziphus mauritiana", "Diospyros kaki",
        "Pistacia vera", "Juglans regia", "Prunus dulcis",
    ],
    "trees": [
        "Azadirachta indica", "Ficus benghalensis", "Ficus religiosa",
        "Ficus elastica", "Ficus auriculata", "Tectona grandis",
        "Eucalyptus tereticornis", "Eucalyptus globulus", "Acacia nilotica",
        "Acacia catechu", "Swietenia mahagoni", "Saraca asoca", "Bauhinia vahlii",
        "Prosopis cineraria", "Tamarix aphylla", "Populus deltoides",
        "Salix tetrasperma", "Mangifera indica", "Madhuca longifolia",
    ],
    "ornamental_and_houseplant": [
        "Rosa chinensis", "Rosa indica", "Jasminum sambac", "Jasminum grandiflorum",
        "Tagetes erecta", "Tagetes minuta", "Hibiscus rosa-sinensis",
        "Nelumbo nucifera", "Nymphaea pubescens", "Helianthus annuus",
        "Bougainvillea glabra", "Dracaena trifasciata", "Epipremnum aureum",
        "Aloe vera", "Spathiphyllum wallisii", "Chlorophytum comosum",
        "Monstera deliciosa", "Philodendron hederaceum", "Ficus lyrata",
        "Catharanthus roseus", "Ixora coccinea", "Bougainvillea spectabilis",
        "Portulaca grandiflora", "Petunia hybrida", "Canna indica",
        "Zinnia elegans", "Catharanthus grandiflorus", "Hoya carnosa",
    ],
    "medicinal": [
        "Ocimum tenuiflorum", "Ocimum sanctum", "Withania somnifera",
        "Curcuma longa", "Zingiber officinale", "Bacopa monnieri",
        "Ashwagandha", "Andrographis paniculata", "Azadirachta indica",
        "Aloe vera", "Ocimum basilicum", "Tulsi", "Moringa oleifera",
        "Phyllanthus amarus", "Sida cordifolia", "Tinospora cordifolia",
        "Aegle marmelos", "Justicia adhatoda", "Picrorhiza kurroa",
        "Rauvolfia serpentina", "Coptis teeta", "Santalum album",
    ],
    "aquatic_and_misc": [
        "Nelumbo nucifera", "Nymphaea pubescens", "Lemna minor",
        "Eichhornia crassipes", "Cyperus papyrus", "Typha angustifolia",
    ],
}


def vernacular_for(key: int) -> str | None:
    """Best English vernacular name GBIF holds for a taxon, if any."""
    try:
        rows = gbif(f"/species/{key}/vernacularNames", {"limit": 50})
    except RuntimeError:
        return None
    candidates = [r for r in rows.get("results", []) if r.get("vernacularName")]
    if not candidates:
        return None
    for row in candidates:
        if (row.get("language") or "").lower().startswith("en"):
            return row["vernacularName"]
    return candidates[0]["vernacularName"]


def parents_for(key: int) -> dict[str, str]:
    """kingdom -> genus hierarchy as GBIF reports it."""
    try:
        rows = gbif(f"/species/{key}/parents")
    except RuntimeError as exc:
        log.warning("parents lookup failed for %s: %s", key, exc)
        return {}
    results = rows.get("results", []) if isinstance(rows, dict) else rows
    hierarchy = {}
    for row in results:
        if not isinstance(row, dict):
            continue
        rank = (row.get("rank") or "").upper()
        name = row.get("name")
        if rank and name and rank not in hierarchy:
            hierarchy[rank] = name
    return hierarchy


def resolve(name: str) -> dict | None:
    """Match a name, then read the accepted record. None if GBIF has no match."""
    try:
        match = gbif("/species/match", {"name": name, "kingdom": "Plantae",
                                        "strict": "false"})
    except RuntimeError as exc:
        log.error("match failed for %r: %s", name, exc)
        return None

    if match.get("matchType") == "NONE" or not match.get("usageKey"):
        return None

    key = int(match["usageKey"])
    try:
        detail = gbif(f"/species/{key}")
    except RuntimeError as exc:
        log.error("detail failed for %r (key %s): %s", name, key, exc)
        return None

    accepted_name = detail.get("canonicalName") or match.get("canonicalName")
    authorship = detail.get("authorship") or ""
    scientific = detail.get("scientificName") or accepted_name or name
    canonical = detail.get("canonicalName") or accepted_name or name

    genus = canonical.split(" ")[0] if canonical else match.get("genus")
    hierarchy = parents_for(key)

    return {
        "gbif_key": str(key),
        "scientific_name": scientific,
        "canonical_name": canonical,
        "authorship": authorship,
        "rank": (detail.get("rank") or "").upper(),
        "taxonomic_status": (detail.get("taxonomicStatus") or "ACCEPTED").upper(),
        "genus": genus,
        "species": canonical,
        "family": hierarchy.get("FAMILY") or match.get("family"),
        "order": hierarchy.get("ORDER") or match.get("order"),
        "class": hierarchy.get("CLASS"),
        "phylum": hierarchy.get("PHYLUM"),
        "kingdom": hierarchy.get("KINGDOM") or "Plantae",
        "vernacular_name": vernacular_for(key),
        "dataset_key": GBIF_DATASET_KEY,
        "published_in": detail.get("publishedIn"),
        "slug": slugify(canonical or name),
        "matched_query": name,
        "match_type": match.get("matchType"),
        "confidence": match.get("confidence"),
        "retrieved_at": utc_now(),
        "source": "gbif",
        "license": GBIF_LICENSE,
        "imported_by": "import_crop_species.py",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--only", default="",
                        help="comma-separated substrings to restrict the import")
    args = parser.parse_args()

    wanted: dict[str, str] = {}
    for name, (group, _crops) in MODEL_CROPS.items():
        wanted[name] = group
    for group, names in PRIORITY_GROUPS.items():
        for name in names:
            wanted.setdefault(name.strip(), group)

    # Drop obvious placeholder/duplicate entries that are not binomials.
    cleaned: dict[str, str] = {}
    for name, group in wanted.items():
        stripped = name.strip()
        if len(stripped.split(" ")) < 2:
            log.warning("skipping non-binomial request %r", stripped)
            continue
        cleaned[stripped] = group

    if args.only:
        needles = [n.strip().lower() for n in args.only.split(",") if n.strip()]
        cleaned = {n: g for n, g in cleaned.items()
                   if any(needle in n.lower() for needle in needles)}

    existing = read_json(STAGE_PATH, []) or []
    known_keys = {str(r.get("gbif_key")) for r in existing}
    known_slugs = {r.get("slug") for r in existing}
    log.info("staging currently holds %d records", len(existing))

    added: list[dict] = []
    skipped: list[str] = []
    unresolved: list[str] = []

    for index, (name, group) in enumerate(sorted(cleaned.items()), start=1):
        record = resolve(name)
        time.sleep(REQUEST_PAUSE)
        if record is None:
            unresolved.append(name)
            log.warning("[%d/%d] UNRESOLVED %s", index, len(cleaned), name)
            continue
        if record["gbif_key"] in known_keys or record["slug"] in known_slugs:
            skipped.append(name)
            log.info("[%d/%d] already present: %s -> %s", index, len(cleaned),
                     name, record["canonical_name"])
            continue
        record["group"] = group
        if record["rank"] not in ("SPECIES", "SUBSPECIES", "VARIETY"):
            unresolved.append(f"{name} (rank={record['rank']})")
            log.warning("[%d/%d] not a species-rank record: %s -> %s (%s)",
                        index, len(cleaned), name, record["canonical_name"],
                        record["rank"])
            continue
        added.append(record)
        known_keys.add(record["gbif_key"])
        known_slugs.add(record["slug"])
        log.info("[%d/%d] + %s -> %s  [%s]", index, len(cleaned), name,
                 record["canonical_name"], group)

    log.info("resolved=%d added=%d already_present=%d unresolved=%d",
             len(cleaned), len(added), len(skipped), len(unresolved))

    if args.dry_run:
        log.info("dry run - staging file untouched")
        for record in added:
            log.info("  would add %s (%s)", record["canonical_name"],
                     record["group"])
        return 0

    if added:
        write_json(STAGE_PATH, existing + added)
        log.info("wrote %s (%d records, +%d)", STAGE_PATH,
                 len(existing) + len(added), len(added))

    write_json(RAW_DIR / "crop_species_report.json", {
        "generated_at": utc_now(),
        "requested": len(cleaned),
        "added": len(added),
        "already_present": len(skipped),
        "unresolved": unresolved,
        "added_records": [
            {"requested": r["matched_query"], "accepted_name": r["canonical_name"],
             "slug": r["slug"], "gbif_key": r["gbif_key"], "group": r["group"],
             "match_type": r["match_type"], "confidence": r["confidence"]}
            for r in added],
    })
    log.info("wrote %s", RAW_DIR / "crop_species_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
