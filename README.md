# PlantDoctor

<div align="center">
  <img src="https://images.unsplash.com/photo-1466692476868-aef1dfb1e735?auto=format&fit=crop&w=1200&q=80" alt="Plants and leaves" width="100%" />
</div>

<p align="center">
  <strong>Plant health intelligence for curious growers</strong><br />
  A simple, reliable plant-information platform built with Flutter and FastAPI.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.13+-02569B?logo=flutter&logoColor=white" />
  <img alt="FastAPI" src="https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white" />
  <img alt="Python" src="https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white" />
  <img alt="Android" src="https://img.shields.io/badge/Android-Release-3DDC84?logo=android&logoColor=white" />
</p>

## Overview

PlantDoctor is a plant-learning and care-support project designed to help people:

- browse a curated plant catalog
- understand plant care and disease patterns
- explore local plant health guidance safely
- keep the project simple, offline-friendly, and easy to extend

This repository contains a compact monorepo with:

- a Flutter mobile app for Android
- a FastAPI backend for app services and API endpoints
- plant data models and curated reference content
- a clear, educational approach that avoids unsafe treatment claims

> PlantDoctor is an educational plant-information tool, not a prescription medical system or a complete global botanical database.

---

## Key Features

- Plant browser with search and categories
- Plant detail cards with care summaries
- Disease-by-plant lookup and education-focused guidance
- Local, offline-first plant reference content
- API-ready backend structure for expansion
- Clean separation between app UI, services, and data

---

## Architecture

```mermaid
flowchart LR
  A[Mobile App<br/>Flutter] --> B[PlantDatabase<br/>Curated Catalog]
  A --> C[Plant Detail UI]
  A --> D[Disease by Plant]
  E[FastAPI Backend] --> F[Plant API]
  E --> G[Health / App Services]
  B --> H[Local Plant Data]
  F --> I[Plant and Care Metadata]
  I --> J[Educational Guidance]
```

### System block diagram

```mermaid
block-beta
  columns 4
  A[User] --> B[Flutter App]
  B --> C[Local Plant Data]
  B --> D[Plant Search]
  B --> E[Plant Details]
  B --> F[Disease Lookup]
  F --> G[Care Guidance]
  H[FastAPI API] --> I[Plant Services]
  I --> J[Metadata + Health Data]
```

### App flow

```mermaid
sequenceDiagram
  participant U as User
  participant M as Mobile App
  participant DB as Plant Database
  participant API as FastAPI Backend

  U->>M: Open app
  M->>DB: Load plant catalogue
  U->>M: Search plant or disease
  M->>DB: Filter and fetch details
  DB-->>M: Plant info + care guidance
  M-->>U: Display results
  U->>API: Optional server health / metadata request
  API-->>U: API response
```

---

## Technology Stack

### Mobile
- Flutter
- Dart
- Material UI
- SQLite-backed local data patterns
- Android-focused release flow

### Backend
- Python 3.11+
- FastAPI
- SQLAlchemy patterns and app services
- REST-style API endpoints

---

## Repository Layout

```text
PLANT/
├── backend/                 # FastAPI backend services
│   ├── app/
│   ├── alembic/
│   └── requirements.txt
├── mobile/                  # Flutter Android app
│   ├── lib/
│   ├── test/
│   ├── docs/
│   └── pubspec.yaml
├── data/                    # Data and imported content
├── docs/                    # Extra docs and notes
├── scripts/                 # data and import scripts
├── .gitignore
├── PROJECT_AUDIT.md
├── README.md
└── server/                 # app server assets / support code
```

---

## Quick Start

### 1) Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 2) Mobile app

```bash
cd mobile
flutter pub get
flutter run
```

### 3) Build Android APK

```bash
cd mobile
flutter build apk --release
```

The release APK is generated in:

```text
mobile/build/app/outputs/flutter-apk/
```

---

## Screenshots

<div align="center">
  <table>
    <tr>
      <td><img src="https://images.unsplash.com/photo-1466692476868-aef1dfb1e735?auto=format&fit=crop&w=800&q=80" alt="Plant cover" width="400" /></td>
      <td><img src="https://images.unsplash.com/photo-1501004318641-b39e6451bec6?auto=format&fit=crop&w=800&q=80" alt="Plants in sunlight" width="400" /></td>
    </tr>
    <tr>
      <td><img src="https://images.unsplash.com/photo-1466692476868-aef1dfb1e735?auto=format&fit=crop&w=800&q=80" alt="Plant learning" width="400" /></td>
      <td><img src="https://images.unsplash.com/photo-1471193945509-9ad0617afabf?auto=format&fit=crop&w=800&q=80" alt="Healthy green leaves" width="400" /></td>
    </tr>
  </table>
</div>

---

## Safety & Scope

This project intentionally focuses on:

- educational plant information
- general care guidance
- disease awareness and prevention ideas
- safe, non-prescription guidance phrasing

It does not claim to be:

- an exhaustive global database of every species on Earth
- a regulated medical treatment system
- an exact diagnosis engine for human or animal medicine
- a prescription-grade dosage platform

---

## Why this project

The goal is to keep the product practical and trustworthy:

- simple to understand
- easy to run locally
- easy to extend with more plant reference content
- built around a clear educational experience rather than risky overpromises

---

## Roadmap

- expand the curated plant catalogue
- add more plant-disease mapping
- improve search, tags, and browsing UX
- strengthen backend API endpoints
- add more mobile app polish and release packaging

---

## License

This project is intended as a learning and plant-information application. Licensing details should be reviewed before commercial distribution.

---

## Contributing

Contributions are welcome for:

- plant data improvements
- UI improvements
- backend API refinements
- documentation updates
- better educational safety language

---

## Contact

Project owner: Vansh Dhiman

GitHub: https://github.com/Powerisvansh/Plant
