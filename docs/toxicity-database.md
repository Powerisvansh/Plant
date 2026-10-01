# Toxicity database — current state and the UNKNOWN rule

**Status: EMPTY. `toxicity_profiles` = 0 rows, `toxicity_parts` = 0 rows,
`human_safety` = 0 rows, `pet_safety` = 0 rows, `livestock_safety` = 0 rows,
`first_aid_records` = 0 rows.**

The `plants` table does carry a `toxicity_status` column and it is populated for
all 3,900 records — every value is currently `UNKNOWN`. That is the correct
value, and this document explains why it must stay `UNKNOWN` until a real source
is attached.

## The rule that matters most: UNKNOWN ≠ SAFE

A plant with no toxicity information must never be shown as safe. The app
returns, verbatim:

> **Toxicity status: Unknown**
> Do not consume or use medicinally without independent verification.

The converse mistake is just as bad and easier to make: **absence from a toxic
list is not evidence of safety.** ASPCA's list is registered as a source
(`aspca_toxic_plants`) and is used as a *check* — a hit upgrades a record, a miss
changes nothing. A plant missing from that list stays `UNKNOWN`.

## Allowed values

`plants.toxicity_status` is constrained to:

| Value | Meaning |
|---|---|
| `NON_TOXIC_REPORTED` | a source explicitly reports it as non-toxic for the relevant subject |
| `TOXIC` | documented toxicity with a named compound or clinical effect |
| `POTENTIALLY_TOXIC` | documented concern but conditional (dose, part, or route dependent) |
| `UNKNOWN` | no reliable information — **the default** |

`scripts/validate_plants.py` fails the build if any value falls outside this set,
so a typo cannot silently become a fifth meaning.

## Subject specificity

Toxicity is not a property of a plant in the abstract — it is a property of a
plant *to a subject*. The schema separates it:

* `toxicity_profiles` — `toxicity_status`, `toxic_compounds`, `exposure_routes`,
  `symptoms`, `severity`, `safety_warning`
* `toxicity_parts` — which plant part carries the risk (leaf, seed, sap, root, …)
* `human_safety`, `pet_safety`, `livestock_safety` — per-subject records
* `first_aid_records` — exposure response

A plant can be `NON_TOXIC_REPORTED` for pets and `POTENTIALLY_TOXIC` for
livestock. Collapsing that into one flag would be a safety bug, so the app shows
the three subjects separately and shows `Unknown` for any subject with no
record.

## Medicinal use

`medicinal_use` is only populated where a source documents it, and it is always
displayed next to the toxicity status. Traditional use is reported as reported
use — never as an endorsement, and never as a dose. The specification's ban on
inventing treatment doses applies with full force to herbal medicine, which is
the more likely place for a harmful invention.

## What the app shows today

For all 3,900 plants:

```
Toxicity status          Unknown
Human safety             Not verified
Pet safety               Not verified
Livestock safety         Not verified
Dangerous parts          Not verified

Do not consume or use medicinally without independent verification.
```

## Plan to close the gap

1. Import pet-safety records from the registered ASPCA source, keeping the
   per-subject split.
2. Add a human/livestock safety source. This needs a properly licensed
   toxicological reference; none is registered yet, and none will be invented.
3. Populate `toxic_parts` and `toxic_compounds` only where a source names them.
4. Record `first_aid` information from official poison-control material, with
   the jurisdiction and the verification date.
5. `UNKNOWN` is never overwritten in bulk. Promotion to a stronger status is a
   per-record, per-source decision recorded in `verification_records`.

The rule for the whole section: an empty toxicity table is a known, displayed
limitation. A confidently wrong one is a defect.
