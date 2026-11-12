/// Camera feel constants for the parcel-world renderer.
///
/// Camera behaviour is app feel rather than game content, so it stays in
/// code; every ambient animation and progression value lives in the JSON
/// content layer (`assets/content/ambience.json`) instead.
library;

/// Furthest zoom-out allowed by every zoom input (pinch, wheel, trackpad).
const double cameraMinZoom = 0.42;

/// Furthest zoom-in allowed by every zoom input.
const double cameraMaxZoom = 4.0;

/// How far past the charted parcels' bounding box the camera centre
/// may travel while panning, in world px: a band of fog wide enough
/// to appreciate the boundary, narrow enough that the map can never
/// be panned out of view. Panning is otherwise unbounded — the world
/// is fog to infinity.
const double cameraChartedMargin = 256;

/// Mouse-wheel zoom responsiveness: scroll distance is converted to a zoom
/// factor through `exp(-delta * sensitivity)`. Larger values zoom faster
/// per notch.
const double cameraWheelZoomSensitivity = 0.0015;
