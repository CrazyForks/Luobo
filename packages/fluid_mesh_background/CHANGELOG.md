## 0.1.0

* First release.
* `FluidBackground` — fluid mesh shader background with palette extraction and
  a soft-blob fallback path.
* `FluidBackgroundScope` — shares one monotonic `FluidClock` across a subtree;
  pauses on `TickerMode`.
* `FluidClock` — monotonically increasing seconds that never wrap (the
  prerequisite for seamless noise animation).
* `FluidPalette` — 4-colour extraction with an LRU cache, reusing the caller's
  own `ImageProvider`.
* `FluidBackgroundEvents.onEvent` — optional observability hook (no logging
  dependency).
* `FluidBackground.seedForIndex` — 45°-stepped per-item seeds so neighbouring
  cards never share one pattern.
* Bundled `shaders/fluid_mesh.frag`; falls back to the painter when the shader
  is unavailable.
