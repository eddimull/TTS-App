import 'package:flutter/cupertino.dart';

/// Dark-mode-safe text/label colors.
///
/// `CupertinoColors` label colors are [CupertinoDynamicColor]s: they only adapt
/// to light/dark mode when `.resolveFrom(context)` is called. Used raw in a
/// `TextStyle` (e.g. `color: CupertinoColors.secondaryLabel`) they silently pin
/// to the light variant, which renders dim and low-contrast on dark
/// backgrounds.
///
/// These getters resolve against the current [BuildContext], so call sites can
/// write `color: context.secondaryText` and never forget to resolve.
extension AppTextColors on BuildContext {
  /// Primary label color. Adapts to light/dark mode.
  Color get primaryText => CupertinoColors.label.resolveFrom(this);

  /// Secondary (subtitle) label color. Adapts to light/dark mode.
  Color get secondaryText => CupertinoColors.secondaryLabel.resolveFrom(this);

  /// Tertiary label color — for the dimmest readable text (captions, chevrons).
  Color get tertiaryText => CupertinoColors.tertiaryLabel.resolveFrom(this);

  /// Quaternary label color — the dimmest label tier (placeholders, disabled).
  Color get quaternaryText =>
      CupertinoColors.quaternaryLabel.resolveFrom(this);

  /// Placeholder text color (e.g. unfilled text fields).
  Color get placeholderText =>
      CupertinoColors.placeholderText.resolveFrom(this);
}
