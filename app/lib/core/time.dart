import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Time handling.
///
/// All persisted timestamps are UTC ISO-8601 (`...Z`). Display times are
/// rendered in the pharmacy's configured timezone (default `Africa/Accra`).
abstract class Clock {
  /// Current UTC time.
  DateTime nowUtc();

  /// Current time in the pharmacy's configured timezone.
  DateTime nowLocal();
}

class SystemClock implements Clock {
  SystemClock({String timezoneName = 'Africa/Accra'}) {
    tzdata.initializeTimeZones();
    _location = tz.getLocation(timezoneName);
  }

  tz.Location _location = tz.UTC;

  set timezone(String name) {
    try {
      _location = tz.getLocation(name);
    } catch (_) {
      _location = tz.UTC;
    }
  }

  String get timezoneName => _location.name;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime nowLocal() => tz.TZDateTime.now(_location);
}

/// ISO-8601 helpers shared by the JSON store and the sync engine.
class IsoTime {
  static String format(DateTime utc) => utc.toUtc().toIso8601String();

  static DateTime? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static String dateOnly(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  static String timeOnly(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}
