/// Result type for domain operations.
///
/// Never throws for expected business failures; use [Err] with an
/// [OtcmsError] carrying a stable [code] so callers can branch reliably.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T get value => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final error) => throw StateError('Result is Err: ${error.message}'),
      };

  OtcmsError get error => switch (this) {
        Ok<T>() => throw StateError('Result is Ok'),
        Err<T>(:final error) => error,
      };
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.error);
  final OtcmsError error;
}

/// Domain error with a stable, machine-readable code.
class OtcmsError {
  const OtcmsError(this.code, this.message, {this.details});

  /// Stable code, e.g. `product_inactive`, `insufficient_stock`,
  /// `batch_expired`, `invoice_collision`, `network_offline`.
  final String code;
  final String message;
  final Object? details;

  bool get isNetworkError => code == 'network_offline' || code == 'network_timeout';

  @override
  String toString() => 'OtcmsError($code): $message';

  /// Common error constructors
  factory OtcmsError.network([String? message]) =>
      OtcmsError('network_offline', message ?? 'You are offline. Working from local data.');

  factory OtcmsError.validation(String message, {Object? details}) =>
      OtcmsError('validation', message, details: details);

  factory OtcmsError.insufficientStock([String message = 'Insufficient stock.']) =>
      OtcmsError('insufficient_stock', message);

  factory OtcmsError.batchExpired([String message = 'Batch has expired.']) =>
      OtcmsError('batch_expired', message);

  factory OtcmsError.notFound(String entity) =>
      OtcmsError('not_found', '$entity not found.');
}

/// Convenience constructors used inside services.
Result<T> ok<T>(T value) => Ok<T>(value);
Result<T> fail<T>(OtcmsError error) => Err<T>(error);
