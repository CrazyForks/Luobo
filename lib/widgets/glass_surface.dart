import 'package:flutter/material.dart';

/// BackdropFilter-free solid bottom sheet. Kept as a drop-in replacement for
/// the previous frosted-glass wrapper so all call sites can switch back to
/// solid backgrounds without touching each file.
Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor ?? Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: builder(context),
    ),
  );
}
