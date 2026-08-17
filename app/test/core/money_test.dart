import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/core/money.dart';

void main() {
  group('Money', () {
    test('formats pesewas with symbol and thousands separators', () {
      expect(const Money(3380).format(), '₵33.80');
      expect(const Money(1454).format(), '₵14.54');
      expect(const Money(0).format(), '₵0.00');
      expect(const Money(123456789).format(), '₵1,234,567.89');
    });

    test('parses decimal strings and numbers safely', () {
      expect(Money.fromString('33.8'), const Money(3380));
      expect(Money.fromString('14.54'), const Money(1454));
      expect(Money.fromDouble(33.8), const Money(3380));
      expect(Money.fromDouble(50), const Money(5000));
      expect(Money.tryParse('₵1,234.56'), const Money(123456));
      expect(Money.tryParse('junk'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('-5'), isNull);
    });

    test('integer arithmetic never loses precision', () {
      const a = Money(1000); // ₵10.00
      const b = Money(500); // ₵5.00
      expect(a + b, const Money(1500));
      expect(a - b, const Money(500));
      expect(a * 3, const Money(3000));
      expect(const Money(3380) + const Money(1454) + const Money(5000), const Money(9834));
    });

    test('comparison operators', () {
      expect(const Money(2000) > const Money(1000), isTrue);
      expect(const Money(2000) == const Money(2000), isTrue);
      expect(const Money(199) < const Money(200), isTrue);
    });
  });
}