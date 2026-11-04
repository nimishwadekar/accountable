/// Tuning constants for the parcel-world renderer.
///
/// Every ambient animation and camera feel knob lives here so the world's
/// pacing can be adjusted in one place. All durations are in seconds of
/// real time and are independent of frame rate: the ambient clock converts
/// elapsed real time into "animation seconds" once, and every animation
/// reads only that clock.
///
/// Small integer multipliers used purely to scramble per-tile phases (for
/// example `origin.column * 3 + origin.row * 7`) are intentionally not
/// listed here — they reshuffle randomness, not pacing.
library;

/// Global multiplier applied to real elapsed time before it reaches any
/// ambient animation. `1.0` animates in real time; `0.5` halves the speed
/// of water, wind, and pedestrians together.
const double ambientTimeScale = 1.0;

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

/// Furthest zoom-out allowed by every zoom input (pinch, wheel, trackpad).
const double cameraMinZoom = 0.42;

/// Furthest zoom-in allowed by every zoom input.
const double cameraMaxZoom = 3.2;

/// Mouse-wheel zoom responsiveness: scroll distance is converted to a zoom
/// factor through `exp(-delta * sensitivity)`. Larger values zoom faster
/// per notch.
const double cameraWheelZoomSensitivity = 0.0015;

// ---------------------------------------------------------------------------
// Water shimmer
// ---------------------------------------------------------------------------

/// Number of diagonal shimmer bands across the water. Bands brighten out
/// of phase, so a higher count gives finer, slower-moving ripples.
const int waterShimmerBands = 6;

/// Seconds for the shimmer's brightness wave to sweep the full band cycle.
const double waterShimmerPeriod = 6.5;

/// Peak overlay opacity of the brightest band. Keep subtle — this sits on
/// top of the water tiles.
const double waterShimmerMaxOpacity = 0.08;

/// Tint of the shimmer overlay (a near-white, faintly blue highlight).
const int waterShimmerColorR = 235;
const int waterShimmerColorG = 245;
const int waterShimmerColorB = 250;

// ---------------------------------------------------------------------------
// Vegetation sway
// ---------------------------------------------------------------------------

/// Peak sway angle in radians (`0.045` ≈ 2.6°), applied around the
/// sprite's ground anchor.
const double vegetationSwayMaxAngle = 0.045;

/// Base sway frequency in radians per second; each plant adds up to
/// [vegetationSwayFrequencySteps] × [vegetationSwayFrequencyStep] on top so
/// neighbours move out of step.
const double vegetationSwayBaseFrequency = 1.1;
const int vegetationSwayFrequencySteps = 7;
const double vegetationSwayFrequencyStep = 0.13;

// ---------------------------------------------------------------------------
// Ambient pedestrians
// ---------------------------------------------------------------------------

/// Sprite size multiplier relative to the standard 128×64 tile render
/// scale. A 24×32 character frame at `1.7` reads as roughly two-thirds of
/// a small building's height.
const double pedestrianSpriteScale = 0.7;

/// Walk-cycle frame rate in frames per second (the pack has 4 frames per
/// direction).
const double pedestrianWalkFrameRate = 7;

/// Walking speed in cells per second, chosen uniformly from
/// [pedestrianSpeedMin] to [pedestrianSpeedMin] + [pedestrianSpeedRange].
const double pedestrianSpeedMin = 0.55;
const double pedestrianSpeedRange = 0.35;

/// One pedestrian per this many connected road cells…
const int pedestrianRoadCellsPerPerson = 6;

/// …capped at this many in total.
const int pedestrianMaxCount = 10;

/// Lateral wander in world pixels so people do not march on the exact
/// centre line of a road.
const double pedestrianLateralWanderX = 10;
const double pedestrianLateralWanderY = 6;

// ---------------------------------------------------------------------------
// Land fading
// ---------------------------------------------------------------------------

/// Overlay that fades unowned land toward the map background. Applied once
/// over each composed cell so layered shore pieces fade like plain ground.
const int unownedLandWashAlpha = 0x4F;
const int unownedLandWashRed = 0xB5;
const int unownedLandWashGreen = 0xDC;
const int unownedLandWashBlue = 0xCF;
