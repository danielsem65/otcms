import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/core/ids.dart';

void main() {
  group('InvoiceNumberGenerator', () {
    test('generates the expected daily format', () {
      final gen = InvoiceNumberGenerator(deviceId: 'dev_AB12CD34EF56');
      final number = gen.next(DateTime(2026, 8, 17), 41);
      // Prefix = first 4 alphanumerics of the device id, uppercased.
      expect(number, 'INV-20260817-DEVA-0042');
      expect(InvoiceNumberGenerator.isValid(number), isTrue);
    });

    test('generates distinct numbers across devices offline', () {
      final a = InvoiceNumberGenerator(deviceId: 'dev_AAAA1111BBBB');
      final b = InvoiceNumberGenerator(deviceId: 'dev_BBBB2222CCCC');
      final na = a.next(DateTime(2026, 8, 17), 0);
      final nb = b.next(DateTime(2026, 8, 17), 0);
      expect(na, isNot(nb));
      expect(InvoiceNumberGenerator.isValid(na), isTrue);
      expect(InvoiceNumberGenerator.isValid(nb), isTrue);
    });

    test('monotonic sequence per device per day', () {
      final gen = InvoiceNumberGenerator(deviceId: 'dev_AB12CD34EF56');
      final first = gen.next(DateTime(2026, 8, 17), 99);
      final second = gen.next(DateTime(2026, 8, 17), 100);
      expect(first, 'INV-20260817-DEVA-0100');
      expect(second, 'INV-20260817-DEVA-0101');
    });

    test('rejects malformed invoice numbers', () {
      expect(InvoiceNumberGenerator.isValid('INV-2026-AB12-0001'), isFalse);
      expect(InvoiceNumberGenerator.isValid('INV-20260817-AB12-004'), isFalse);
      expect(InvoiceNumberGenerator.isValid(''), isFalse);
    });
  });

  group('Ids', () {
    test('produces typed prefixed ids', () {
      expect(Ids.productId(), startsWith('prod_'));
      expect(Ids.operationId(), startsWith('op_'));
      expect(Ids.saleId(), startsWith('sale_'));
      expect(Ids.movementId(), startsWith('mov_'));
      expect(Ids.batchId(), startsWith('batch_'));
      expect(Ids.deviceId(), startsWith('dev_'));
    });

    test('ids are unique', () {
      final ids = {for (var i = 0; i < 1000; i++) Ids.productId()};
      expect(ids.length, 1000);
    });
  });
}