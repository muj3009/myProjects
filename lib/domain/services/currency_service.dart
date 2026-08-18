/// Centralizes currency-aware rounding/formatting so no other file does raw
/// `fare / distance` arithmetic without going through the same rounding rule
/// (spec section 42 — "Do not hard-code calculations everywhere").
///
/// Only GBP is implemented today; the symbol/rounding-unit table is the
/// extension point for future currencies rather than scattering `if (code ==
/// 'GBP')` checks through rule/parser code.
class CurrencyService {
  const CurrencyService._();

  static const String defaultCurrencyCode = 'GBP';

  static const Map<String, String> _symbols = {
    'GBP': '£',
    'EUR': '€',
    'USD': r'$',
  };

  static String symbolFor(String currencyCode) =>
      _symbols[currencyCode] ?? currencyCode;

  /// Rounds a £/mile or £/hour figure to the nearest penny (2dp) to avoid
  /// binary floating-point artefacts (e.g. 1.9999999999) causing an
  /// incorrect FAIL right at a threshold boundary.
  static double roundToPence(double amount) {
    return double.parse(amount.toStringAsFixed(2));
  }

  static String format(double amount, {String currencyCode = defaultCurrencyCode}) {
    return '${symbolFor(currencyCode)}${amount.toStringAsFixed(2)}';
  }
}
