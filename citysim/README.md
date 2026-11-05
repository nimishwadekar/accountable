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

Saves are the four CSV sheet documents (`UserData`, `Tiles`,
`OwnedParcels`, `Projects`) written by the editor server to
`assets/test_sheets/` — the game holds the world in memory and pushes
every save through the server; a reset never touches any Accountable
data. The
content editor dashboard runs on port 9200 from `tool/content_editor/`
(`dart run tool/content_editor/server.dart`, with the dashboard built via
`flutter build web -t lib/editor/main.dart -o build/editor`).
