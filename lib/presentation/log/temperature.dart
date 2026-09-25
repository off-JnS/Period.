import 'package:intl/intl.dart';

/// The lowest temperature accepted, in hundredths of °C. Anything lower is a
/// typo, not a reading (docs/cycle-logic.md §9).
const lowestTemperatureCenti = 3400;

/// The highest temperature accepted, in hundredths of °C.
const highestTemperatureCenti = 4300;

/// What was typed into the temperature field.
sealed class TemperatureInput {
  const TemperatureInput();
}

/// Nothing typed: no reading.
class NoTemperature extends TemperatureInput {
  /// Creates the result.
  const NoTemperature();
}

/// A plausible reading.
class ValidTemperature extends TemperatureInput {
  /// Creates the result.
  const ValidTemperature(this.centi);

  /// In hundredths of °C.
  final int centi;
}

/// Not a number, or outside 34–43 °C: refused rather than stored.
class InvalidTemperature extends TemperatureInput {
  /// Creates the result.
  const InvalidTemperature();
}

/// Reads what she typed. Accepts a comma or a point as the decimal mark, so
/// "36,45" and "36.45" both work whatever the phone's language, and up to two
/// decimals. Works in whole hundredths throughout, so no rounding can creep in.
TemperatureInput parseTemperature(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (text.isEmpty) return const NoTemperature();

  final match = RegExp(r'^(\d{2})(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return const InvalidTemperature();
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '0').padRight(2, '0');
  final centi = whole * 100 + int.parse(fraction);

  if (centi < lowestTemperatureCenti || centi > highestTemperatureCenti) {
    return const InvalidTemperature();
  }
  return ValidTemperature(centi);
}

/// "36.45" or "36,45", in [locale]'s decimal mark, without the unit.
String formatTemperatureNumber(int centi, String locale) =>
    NumberFormat('0.00', locale).format(centi / 100);

/// "36.45 °C" or "36,45 °C".
String formatTemperature(int centi, String locale) =>
    '${formatTemperatureNumber(centi, locale)} °C';
