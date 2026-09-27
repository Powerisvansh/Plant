from __future__ import annotations

import csv
import json
from pathlib import Path

from app.database import engine
from app.models.plant import Plant


def load_plants_from_json(path: str | Path) -> int:
    file_path = Path(path)
    data = json.loads(file_path.read_text(encoding='utf-8'))
    if not isinstance(data, list):
        raise ValueError('JSON file must contain a list of plant objects')

    inserted = 0
    with engine.begin() as conn:
        for item in data:
            conn.execute(Plant.__table__.insert(), [item])
            inserted += 1
    return inserted


def load_plants_from_csv(path: str | Path) -> int:
    file_path = Path(path)
    inserted = 0
    with file_path.open('r', encoding='utf-8', newline='') as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    with engine.begin() as conn:
        for row in rows:
            conn.execute(Plant.__table__.insert(), [row])
            inserted += 1
    return inserted


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Import sample plant data')
    parser.add_argument('path', help='Path to a JSON or CSV file')
    args = parser.parse_args()

    suffix = Path(args.path).suffix.lower()
    if suffix == '.json':
        count = load_plants_from_json(args.path)
    elif suffix == '.csv':
        count = load_plants_from_csv(args.path)
    else:
        raise ValueError('Only .json and .csv files are supported')

    print(f'Imported {count} plant records')
