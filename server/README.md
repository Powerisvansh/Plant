# PlantDoctor Simple Plant Information Server

This is the minimal backend for the PlantDoctor mobile app. It exposes plant information from a local SQLite database and is intentionally limited to plant data only.

Important:
- Authentication is intentionally not implemented.
- OTP, user accounts, doctors, medicines, diagnosis history, admin tools, notifications, payments, Redis, and AI diagnosis are all future work.
- This server is designed to be simple and easy to migrate to PostgreSQL later.

## 1. Install dependencies

From the server directory:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2. Start the server

```bash
export $(grep -v '^#' .env.example | xargs)
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Or:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Swagger UI is available at:

```text
http://localhost:8000/docs
```

## 3. Add plant data

Plant records are stored in SQLite in `server/data/plants.db`.

The server creates the database automatically when it starts if needed.

You can add plant data in either JSON or CSV format.

### JSON example

Create a file like `server/data/plants.json`:

```json
[
  {
    "common_name": "Neem",
    "scientific_name": "Azadirachta indica",
    "hindi_name": "नीम",
    "family": "Meliaceae",
    "genus": "Azadirachta",
    "species": "indica",
    "description": "A widely used medicinal tree with bitter leaves and neem oil.",
    "plant_type": "Tree",
    "sunlight": "Full sun",
    "water_requirement": "Low to moderate",
    "soil_requirement": "Well-drained soil",
    "temperature": "20-35°C",
    "humidity": "Moderate",
    "fertilizer_information": "",
    "growing_information": "",
    "propagation": "Seed or cuttings",
    "common_diseases": "Leaf spot|Powdery mildew",
    "common_pests": "Scale insects|Whiteflies",
    "care_information": "Prune lightly to maintain shape.",
    "image": "",
    "source": "Sample data for development only",
    "verification_status": "sample"
  }
]
```

Then load it using Python:

```bash
python - <<'PY'
import json
from pathlib import Path
from sqlalchemy import create_engine
from app.models.plant import Plant
from app.database import Base

base = Path('data')
base.mkdir(exist_ok=True)
engine = create_engine('sqlite:///data/plants.db')
Base.metadata.create_all(bind=engine)
with open(base / 'plants.json', 'r', encoding='utf-8') as f:
    data = json.load(f)
with engine.begin() as conn:
    for item in data:
        conn.execute(
            Plant.__table__.insert(),
            [item],
        )
print('Loaded plant data')
PY
```

### CSV example

Create a file like `server/data/plants.csv` with columns matching the table fields.

Example:

```csv
common_name,scientific_name,hindi_name,family,genus,species,description,plant_type,sunlight,water_requirement,soil_requirement,temperature,humidity,fertilizer_information,growing_information,propagation,common_diseases,common_pests,care_information,image,source,verification_status
Neem,Azadirachta indica,नीम,Meliaceae,Azadirachta,indica,"A medicinal tree.",Tree,Full sun,Low to moderate,Well-drained soil,20-35°C,Moderate,,,Seed or cuttings,"Leaf spot|Powdery mildew","Scale insects|Whiteflies","Prune lightly to maintain shape.",,Sample data for development only,sample
```

## 4. Test the API

```bash
pytest
```

Or use a browser / curl:

```bash
curl http://localhost:8000/api/v1/plants
curl "http://localhost:8000/api/v1/plants/search?q=neem"
curl http://localhost:8000/health
```

## 5. Find the desktop LAN IP

On Linux:

```bash
hostname -I
```

Or:

```bash
ip addr show
```

Typical output looks like:

```text
192.168.1.25
```

Use that address in the mobile app instead of `127.0.0.1`.

## 6. Connect the mobile app

The phone should connect to the desktop over the local network, for example:

```text
http://192.168.1.25:8000/api/v1/plants
```

Do not use `http://127.0.0.1:8000` when the app is running on a phone.

## 7. API endpoints

### Health

```http
GET /health
```

Returns:

```json
{"status": "ok"}
```

### List plants

```http
GET /api/v1/plants
```

Supports pagination:

```http
GET /api/v1/plants?skip=0&limit=20
```

### Get one plant

```http
GET /api/v1/plants/{id}
```

### Search plants

```http
GET /api/v1/plants/search?q=neem
```

Searches common name, scientific name, Hindi name and family.

## Future features (not yet implemented)

The following features are intentionally left out for now:
- authentication
- signup/login
- OTP
- passwords
- doctors
- medicines
- user profiles
- user accounts
- diagnosis history
- admin dashboard
- notifications
- payments
- Redis
- AI diagnosis backend

These should be added as separate phases later.
