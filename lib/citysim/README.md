# Settlement preview

This is a standalone synthetic-data experiment. It does not import Accountable
screens, account repositories, OAuth, Google Sheets, or transaction models.

Run it separately from the main app:

```sh
flutter run -d web-server --web-port=9101 -t lib/citysim/main.dart
```

The current save uses only the `citysim.parcel-world.v2` browser-preferences
key. Reset affects that key only. The old `citysim.prototype.v1` save remains
untouched after an explicit start-new-world choice. World rules, terrain, and
entities live under `world/`; sprite roles are resolved through its manifest.

The current entry point uses the parcel-world V2: an empty 8×8 starter parcel,
one free center dirt-road tile, purchasable adjacent parcels, connected roads,
road-adjacent buildings, natural water barriers, river bridges, and day-based
construction. Check-in is explicit; advancing simulated days never awards coins.
Debug coin grants are labelled test controls.

The architecture and remaining work are in
[`docs/city_sim/PARCEL_WORLD_IMPLEMENTATION_PLAN.md`](../../docs/city_sim/PARCEL_WORLD_IMPLEMENTATION_PLAN.md).
The V1 save key (`citysim.prototype.v1`) is preserved; V2 writes to a separate
key and requires an explicit choice before starting a new world when a V1 save
exists.
