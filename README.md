# Fermata 🎵

**Fermata** is an offline-first sheet music keeping and practice app built for **Android**. Store, organize, annotate, and practice from your scores.

---

## Architecture & Project Layout

Fermata is organized as a **Dart pub workspace** comprising three main packages:

```
fermata_workspace/
├── app/                          # Flutter UI + composition root + platform adapters
├── packages/fermata_core/        # Pure Dart domain: models, geometry, duplicate rules, repo interfaces
└── packages/fermata_data/        # Pure Dart: drift tables/db/repos, dart:io storage, import pipeline
```

### Layering Rules
1. **`fermata_core` must stay pure Dart.** No `package:flutter`, no `dart:io`, no Drift.
2. **Repository contracts live in core, implementations in data.** UI depends on interfaces, never directly on database implementations.
3. **Everything Fermata owns lives under one root directory** (`<app docs>/fermata`) with relative storage paths.

---

## Key Features

- **Score Import & Duplicate Detection**: Multi-page PDF import, image/bitmap support, exact-hash duplication blocking, and metadata soft-suggestions.
- **High-Performance PDF Viewer**: Custom PDF page rendering via `pdfrx` with size-keyed raster caches and cancellation tokens.
- **Annotation Engine v1**: Multi-layer ink persistence (compact 1/10000 integer JSON), RDP simplification, Catmull-Rom smoothing, pen and highlighter tools with 2-pass Z-ordering (`BlendMode.multiply`).
- **MIDI Layer**: Custom lossless Standard MIDI File (SMF) reader supporting running status, VLQ, zero-velocity note-offs, time/tempo maps, and score interpretation.
- **Tags & Setlists**: Case-insensitive unique tags and ordered setlists with drag-and-drop reordering and contiguous position management.
- **Practice & Pedal Mappings**: Configurable page-turn pedal bindings via `HardwareKeyboard` and practice organization.

---

## Getting Started

### Prerequisites
- **Dart ≥ 3.13** & **Flutter SDK**

### First-Time Setup (Mandatory)
```bash
# 1. Resolve workspace dependencies
dart pub get

# 2. Generate Drift database code
cd packages/fermata_data
dart run build_runner build --delete-conflicting-outputs
cd ../..
```

### Commands

- **Analysis**:
  ```bash
  dart analyze
  cd app && flutter analyze
  ```
- **Tests**:
  ```bash
  cd packages/fermata_core && dart test
  cd packages/fermata_data && dart test
  cd app && flutter test
  ```
- **Run App**:
  ```bash
  cd app && flutter run
  ```

---

## Tech Stack

- **Framework**: Flutter / Dart
- **State Management**: Flutter Riverpod
- **Database & ORM**: Drift (SQLite with WAL & foreign key cascades)
- **PDF Rendering**: `pdfrx`
- **Audio / MIDI**: Custom SMF parser & MIDI score interpretation layer
