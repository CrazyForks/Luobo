/// An Apple-Music-style animated background: colours extracted from an image,
/// laid out as a continuously flowing "fluid mesh" field driven by a fragment
/// shader.
///
/// ```dart
/// import 'package:fluid_mesh_background/fluid_mesh_background.dart';
///
/// FluidBackground(imageUrl: coverUrl, borderRadius: 12)
/// ```
///
/// See the package README for the design notes and tuning guide.
library;

export 'src/fluid_background.dart'
    show FluidBackground, FluidBackgroundScope, FluidBackgroundStyle;
export 'src/fluid_clock.dart' show FluidClock;
export 'src/fluid_events.dart' show FluidBackgroundEvents;
export 'src/fluid_palette.dart' show FluidPalette;
