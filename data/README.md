# `data/` — local runtime data

Nothing in this directory is committed. `.gitignore` excludes
`data/plantdoctor/` and `data/postgres/` entirely.

## Committed (safe, no secrets)

| File | Purpose |
|---|---|
| `seed_species.txt` | Scientific names the plant importer resolves against the GBIF Backbone Taxonomy. One name per line; `#` comments allowed. |
| `sources.json` | The provenance registry: publisher, licence, attribution template, terms URL, `date_accessed` for every external source the knowledge base draws on. |

## Not committed (runtime state)

```
data/plantdoctor/
├── uploads/            # user avatars, saved-plant photos
├── plant-images/       # reference imagery attached to knowledge records
├── diagnosis-images/   # images uploaded for a diagnosis
├── user-avatars/
├── backups/            # pg_dump output (also served by `python -m app.cli backup`)
├── logs/               # rotated application logs, if LOG_FILE is set
└── mail/               # development OTP mailbox: one .eml per message
                        # (only populated when SMTP_HOST is unset)
```

On the Docker stack the same tree lives in the `plantdoctor_uploads` volume at
`/data/plantdoctor`, and in the `plantdoctor_backups` volume for backups.

## The development OTP mailbox

When `SMTP_HOST` is empty the server cannot send mail, so instead of failing it
writes each OTP message to `data/plantdoctor/mail/<timestamp>.eml`. This is a
**development convenience only** — it is how you test the OTP flow without
credentials. It must never be enabled in production; set a real `SMTP_HOST` and
leave `MAILBOX_DIRECTORY` empty there.

Each file contains the real OTP, so the directory is as sensitive as an inbox.
It is covered by `.gitignore` and by the "never commit real user data" rule.

## PostgreSQL cluster

The live cluster created for this project stores its data in
`/plantdoctor-data/database/postgres` (see `docs/DEPLOYMENT.md`). It is
deliberately outside the repository so that `git clean -xdf` can never destroy
the database. `data/postgres/` is reserved for a repository-local cluster if
you prefer one.
