# fluid_mesh_background

An Apple-Music-style animated background for Flutter: **colours extracted from a
cover image, laid out as a continuously flowing "fluid mesh" field**, driven by
a fragment shader.

No discrete shapes — the whole picture is one continuous field that keeps
flowing, which is what makes it read as "flowing" rather than "some circles
moving". Drop-in animated background for cards, hero headers and full-screen
players.

| Shader path (default) | Palette fallback |
|---|---|
| `shaders/fluid_mesh.frag` — value noise + sine warping + grain | soft drifting blobs, used only when the shader cannot be loaded |

## Features

- **Palette extraction** from any `ImageProvider` (your own cache included) —
  nothing is downloaded twice.
- **Continuously flowing**, never loops visibly: the flow is driven by a
  **monotonic clock**, so the noise field never wraps.
- **One clock per subtree** via `FluidBackgroundScope` — N cards cost one
  ticker, and everything pauses on `TickerMode` (hidden tabs, offscreen pages).
- **Per-item variety** via `FluidBackground.seedForIndex`: neighbouring items
  get different directions (45° steps), noise regions and warp phases.
- **Zero logging dependency**: observability events are reported through an
  optional `FluidBackgroundEvents.onEvent` hook.
- Falls back silently when the shader is unavailable (e.g. unsupported render
  backend).

## Install

```yaml
dependencies:
  fluid_mesh_background: ^0.1.0
```

## Usage

```dart
import 'package:fluid_mesh_background/fluid_mesh_background.dart';

FluidBackground(imageUrl: coverUrl, borderRadius: 12)
```

Multiple instances on one screen should share a clock:

```dart
FluidBackgroundScope(
  child: GridView.builder(
    itemCount: covers.length,
    itemBuilder: (_, i) => FluidBackground(
      imageUrl: covers[i],
      seed: FluidBackground.seedForIndex(i), // different pattern per card
    ),
  ),
)
```

Using your own image cache (recommended, avoids a second download):

```dart
FluidBackground(
  imageProvider: CachedNetworkImageProvider(
    url,
    cacheManager: coverCacheManager,
    cacheKey: coverArtCacheKeyFromUrl(url),
  ),
)
```

### Options

| param | default | meaning |
|---|---|---|
| `imageUrl` / `imageProvider` / `colors` | — | colour source; `colors` wins, then `imageProvider`, then `imageUrl` |
| `style` | `FluidBackgroundStyle.standard` | `speed` (0.27 ≈ 30 s per band crossing), `warp` (3.2), `grain` (0.05) |
| `seed` | 0 | per-instance pattern offset — use `seedForIndex(i)` in grids |
| `borderRadius` | 0 | corner radius (clips) |
| `showScrim` | false | dark top-to-bottom overlay for white text on top |
| `useShader` | true | set false to force the fallback painter |
| `clock` | — | explicit `FluidClock`; otherwise the nearest scope, else a private one |

### Observability

```dart
FluidBackgroundEvents.onEvent = (event, payload) {
  myDiagnostics.record(event, payload); // shaderReady / shaderUnavailable / paletteExtract / paletteEvict
};
```

## How it works

- **Why a shader**: "several circles moving" and "flowing sand" are different
  species. Circles are discrete objects with edges — the eye reads them as
  "three circles", and adding texture to a circle does not change that. A fluid
  field has *no shapes to count*; every pixel's colour is decided by noise
  coordinates, so the only thing left to see is motion. That requires
  per-pixel computation — a fragment shader.
- **Why a monotonic clock**: noise is not a periodic function. A 0→1 looping
  `AnimationController` rewinds time at the wrap, which snaps the picture. The
  bundled `FluidClock` returns monotonically increasing seconds and never
  wraps; periodic fallback math is made exactly 2π-periodic instead.
- **Why per-item seeds**: staggering only the time phase leaves the pattern
  structure identical (same direction, same grain). The seed offsets the
  rotation, the noise sampling region and the warp phase — so each item gets a
  genuinely different flow. *Measured lesson: a 66–81 % pixel difference does
  not mean the eye sees a difference; structure does.*

## Tests

The suite lives in `example/test/` — shader assets are only resolvable when the
package is a dependency (which the example is). It verifies the shader actually
*renders* (offscreen pixel sampling: opaque, spatially varied, flowing over
time), the wrap-point seamlessness, clock monotonicity, seed spread and scope
sharing. **Compiling is not rendering** — the pixel-level assertions exist
because "it builds" proved insufficient.

## License

MIT — see [LICENSE](LICENSE).

Note: the source is original work written for this package. The four default
fallback colours are a deliberate palette choice, not extracted from anything.
