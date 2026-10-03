# Limitations

What PlantDoctor AI cannot do, stated plainly. This document is deliberately
unflattering; it is the contract between the app and the person holding the
phone.

## 1. The model recognises 14 crops, not 10,000 species

The knowledge base holds 10,000 real species. The **image model** does not.

The visual model is trained on PlantVillage, which covers 14 crops and 38
`crop___condition` classes. There is no openly licensed image dataset covering
10,000 species, so the model cannot be one.

Consequence: for a mango tree, a gulmohar, or a marigold, the app does **not**
claim a species. It reports what it can see, and it offers the knowledge base as
a *searchable* resource rather than a result. Presenting a species for an
uncovered plant is exactly the failure this project exists to remove.

`10,000 plant records` and `image recognition coverage` are two different
numbers. Only the first is 10,000.

## 2. PlantVillage images are not field photographs

PlantVillage images are largely lab-style: a single leaf, evenly lit, filling
the frame, often on a plain background. A phone photo taken in a field at
morning haze, with two leaves and a shadow, is out of distribution.

Accuracy measured on the held-out PlantVillage test split is therefore an
**upper bound** on field performance. Real-world accuracy will be lower. The
app never presents the test number as a field accuracy claim.

## 3. It is a screener, not a diagnosis

A prediction is a *hypothesis for a human to check*. The app says "possible" and
"consistent with", never "this is" or "you have".

No model can confirm a pathogen from a JPEG. Confirmation needs lab work —
microscopy, culture, or a lab test — and the app says so wherever a disease is
raised.

## 4. "Yellow leaf" is not a diagnosis

Yellowing has many causes — nitrogen deficiency, overwatering, root rot, natural
senescence, nutrient lockout from high pH, spider mites, cold damage. The app
lists these as alternatives and refuses to convert a colour observation into a
single deficiency claim.

## 5. Empty sections stay empty

Treatments, dosages, toxicity profiles, and human/livestock safety records are
**not present in this release**. The app shows "Verified dosage information is
unavailable" and "Toxicity status: Unknown".

It does not substitute a typical dose, a neighbouring crop's dose, a folk remedy,
or a guess. A confident wrong dose is worse than an admitted gap.

## 6. `UNKNOWN` is not `SAFE`

A plant with no toxicity record is shown as `Unknown`, never as safe. Absence
from a published toxic-plant list is not evidence of safety, and the importer is
built so that a list miss cannot promote a record.

## 7. Species confidence is capped on purpose

The morphological classifier can never exceed 0.42 confidence, below the 0.45
uncertainty threshold. Leaf shape alone cannot identify a species, and the cap
exists so the app never launders a shape guess into a name. Only a real model
result may name a species, and even then only within its trained classes.

## 8. A single leaf is rarely enough

Many species are separable by leaf shape; many are not. From one leaf the app
will attempt identification and will say that it may be uncertain. Whole-plant,
flower, fruit, and bark characters carry most of the identifying signal, which
is why multi-photo analysis exists.

## 9. Conflicts are reported, not resolved

When uploaded photos disagree, the app says the images provide conflicting
visual evidence. It does not average them into a confident wrong answer.

## 10. No Internet is required, and none is used

The knowledge base ships inside the app. Photos are processed on-device and are
not uploaded. Release builds do not even request the `INTERNET` permission, so
this is enforced by the platform rather than by policy alone.

A consequence: no content updates until a new release. That is the trade for
guaranteed offline availability.

## 11. Metrics are CPU metrics

Measured latency is from a 4-core desktop CPU, not a phone. Phone performance
will differ, and a low-end device may be several times slower. No inference-time
claim is made for hardware the model was not measured on.

## 12. Measurement limits of the build machine

| Resource | Value | Consequence |
|---|---|---|
| CPU | Intel i5-4590, 4 cores | training is hours, not minutes |
| RAM | 11 GiB total | large models are not trainable here |
| GPU | Intel integrated graphics only | **no CUDA, no GPU training** |
| Disk | one 931 GB disk, 777 GB free | dataset fits; no second disk exists |

The architecture was chosen *because* of this: MobileNetV3-Small is small enough
to train on CPU and fast enough to run on a phone. A larger model would score
better and could not be trained or shipped here.

## 13. What has not been done

* No dose, treatment, or pesticide record exists.
* No human or livestock toxicity data exists.
* No plant, disease, or pest photograph is bundled — all image tables are empty.
* No plant record is marked `VERIFIED`; all 10,000 are `UNVERIFIED` and correctly
  labelled as such.
* Only 4,157 of 10,000 plants have a common name; the rest are searchable by
  scientific name.
* Not tested on a physical phone. The APK builds, but on-device behaviour is
  unverified.

## 14. What would change these

Better field performance needs field photographs, not more epochs. Toxicity and
treatment coverage need licensed sources, not more curation. Species coverage
beyond 14 crops needs a genuinely large licensed image dataset. None of these
are solved by writing more code, and pretending otherwise would be the exact
failure mode this project was built to eliminate.
