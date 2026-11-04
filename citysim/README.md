# Citysim — Parcel World

A standalone, synthetic-data settlement game. Everything for the game lives
in this folder as its own Flutter package, fully isolated from the Accountable
finance app at the repository root: no shared code, saves, OAuth, Sheets, or
financial data.

## Running

From this folder:

```sh
flutter run -d web-server --web-port=9101
```

The Accountable app's development port is 9000 — do not stop or reconfigure
it to run this preview.

## Testing and building

```sh
flutter test
flutter analyze
flutter build web
```

These commands must run from this folder; the root package no longer
includes citysim code or tests.

## Layout

- `lib/` — game code (`world/` rules and state, `rendering/` isometric
  canvas, `content/` the JSON content layer, `editor/` the dashboard).
- `test/` — rule, save, and widget tests.
- `assets/` — organized sprite tree, character frames, the JSON content
  layer, and the unused pack remainder (see `assets/ASSET_NOTICE.md`).
- `docs/` — game mechanics, technical, and content-editor plans.
- `web/` — Flutter web platform scaffolding.

Local saves use the `citysim.parcel-world` browser-storage key only; a
reset never touches any Accountable data.

The planned content editor dashboard will run on port 9200 from
`tool/content_editor/`.
