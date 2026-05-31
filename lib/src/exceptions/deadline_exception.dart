// ─────────────────────────────────────────────────────────────────────────────
// deadline_exception.dart
//
// Custom exception hierarchy for the deadline_future package.
// All exceptions implement [Exception] so they can be caught with
// on Exception { } or individually.
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all exceptions thrown by `deadline_future`.
///
/// Catch this if you want a single handler for any package-level failure:
///
/// ```dart
/// try {
///   final result = await myFuture.withDeadline(timeout);
/// } on DeadlineFutureException catch (e) {
///   log(e.toString());
/// }
/// ```
abstract class DeadlineFutureException implements Exception {
  /// A human-readable description of what went wrong.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// DeadlineExceededException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when the deadline elapsed **and** neither a cached value nor a
/// static fallback was available to satisfy the call.
///
/// This is intentionally different from [TimeoutException]:
/// - It is only thrown as a last resort (cache and fallback are tried first).
/// - It carries precise context about the deadline, the optional [context]
///   label, and the time at which it was generated.
///
/// ### Prevention
///
/// Supply at least one of:
/// - `fallback: yourDefaultValue` — always available, zero latency.
/// - `cacheKey: 'unique_key'` — populated after the first successful call.
///
/// ### Example
///
/// ```dart
/// try {
///   final result = await fetchData().withDeadline(
///     const Duration(seconds: 1),
///     // no fallback, no cacheKey → may throw
///   );
/// } on DeadlineExceededException catch (e) {
///   print('Timed out after ${e.deadline.inMilliseconds}ms — ${e.context}');
/// }
/// ```
final class DeadlineExceededException extends DeadlineFutureException {
  /// The configured deadline that was exceeded.
  final Duration deadline;

  /// Optional free-text label passed via the `context` parameter of
  /// [withDeadline]. Useful for distinguishing multiple call sites in logs.
  final String? context;

  /// UTC timestamp of when the exception was created (≈ when the timer fired).
  final DateTime occurredAt;

  /// Creates a [DeadlineExceededException].
  DeadlineExceededException({
    required this.deadline,
    this.context,
    DateTime? occurredAt,
  }) : occurredAt = occurredAt ?? DateTime.now().toUtc();

  @override
  String get message =>
      'Future did not complete within ${deadline.inMilliseconds}ms'
      '${context != null ? " [context: $context]" : ""}. '
      'Provide a `fallback` value or a `cacheKey` to avoid this exception.';
}

// ─────────────────────────────────────────────────────────────────────────────
// InvalidDeadlineDurationException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown synchronously when the `deadline` [Duration] passed to [withDeadline]
/// is zero or negative.
///
/// A deadline of zero milliseconds would resolve immediately without giving
/// the Future any chance to complete — this is almost certainly a bug.
///
/// ### Example
///
/// ```dart
/// // ❌ This throws synchronously:
/// await myFuture.withDeadline(Duration.zero);
/// await myFuture.withDeadline(const Duration(milliseconds: -500));
/// ```
final class InvalidDeadlineDurationException extends DeadlineFutureException {
  /// The invalid duration that was supplied.
  final Duration duration;

  /// Creates an [InvalidDeadlineDurationException].
  // ignore: prefer_const_constructors_in_immutables
  InvalidDeadlineDurationException(this.duration);

  @override
  String get message =>
      'Deadline duration must be a positive non-zero value; '
      'received ${duration.inMilliseconds}ms. '
      'Use at least Duration(milliseconds: 1).';
}

// ─────────────────────────────────────────────────────────────────────────────
// DeadlineCacheException
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when an internal cache operation fails unexpectedly.
///
/// Under normal circumstances you should never see this; it is here as a
/// defensive measure for future extensibility (e.g. a persistent cache
/// backend that can have I/O errors).
final class DeadlineCacheException extends DeadlineFutureException {
  /// The cache key involved in the failing operation.
  final String? key;

  /// The underlying cause, if available.
  final Object? cause;

  /// Creates a [DeadlineCacheException].
  // ignore: prefer_const_constructors_in_immutables
  DeadlineCacheException({this.key, this.cause});

  @override
  String get message =>
      'An internal cache error occurred'
      '${key != null ? " for key \"$key\"" : ""}.'
      '${cause != null ? " Cause: $cause" : ""}';
}
