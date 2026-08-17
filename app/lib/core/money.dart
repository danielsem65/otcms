/// Money as integer minor units (pesewas / cents).
///
/// All financial math in OTCMS uses integer arithmetic only.
/// Never store or compute totals as `double`.
class Money implements Comparable<Money> {
  const Money(this.pesewas) : assert(pesewas >= 0);

  /// Parse from a decimal string or number, e.g. `"33.8"` or `"14.54"`.
  /// Rounds to the nearest pesewa; never throws for valid numbers.
  factory Money.fromDouble(num value) => Money((value * 100).round());

  factory Money.fromString(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^\d.\-]'), '');
    return Money.fromDouble(double.parse(cleaned));
  }

  /// Minor units (1/100 of the main unit).
  final int pesewas;

  /// Safe parse: returns null instead of throwing.
  static Money? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(RegExp(r'[^\d.\-]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed < 0) return null;
    return Money.fromDouble(parsed);
  }

  Money operator +(Money other) => Money(pesewas + other.pesewas);
  Money operator -(Money other) => Money(pesewas - other.pesewas);
  Money operator *(num factor) => Money((pesewas * factor).round());
  Money operator /(num divisor) => Money(pesewas ~/ divisor);

  @override
  int compareTo(Money other) => pesewas.compareTo(other.pesewas);

  bool operator >(Money other) => pesewas > other.pesewas;
  bool operator <(Money other) => pesewas < other.pesewas;
  bool operator >=(Money other) => pesewas >= other.pesewas;
  bool operator <=(Money other) => pesewas <= other.pesewas;

  bool get isZero => pesewas == 0;

  @override
  bool operator ==(Object other) => other is Money && other.pesewas == pesewas;

  @override
  int get hashCode => pesewas.hashCode;

  /// Renders `₵33.80` with thousands separators.
  String format({String symbol = '₵', bool alwaysShowSymbol = true}) {
    final whole = pesewas ~/ 100;
    final minor = (pesewas % 100).toString().padLeft(2, '0');
    final grouped = _group(whole.toString());
    final sign = alwaysShowSymbol ? symbol : '';
    return '$sign$grouped.$minor';
  }

  /// Renders `33.80` without symbol.
  String formatPlain() => format(alwaysShowSymbol: false);

  /// Compact render for tight UI: `₵33.80`.
  String get ghs => format();

  static String _group(String digits) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  String toString() => format();
}
