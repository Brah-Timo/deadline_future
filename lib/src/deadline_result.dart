import 'package:meta/meta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DeadlineResultSource
// ─────────────────────────────────────────────────────────────────────────────

/// Describes where the resolved value inside a [DeadlineResult] came from.
///
/// Use this to make informed UI decisions (e.g. show a "stale data" badge
/// when [fallback] or [cached] is returned).
enum DeadlineResultSource {
  /// The original [Future] completed **before** the deadline. ✅
  ///
  /// This is the happy path — the value is fresh and authoritative.
  completed,

  /// The deadline elapsed and the value is the **static fallback** supplied
  /// by the caller. 🛡️
  ///
  /// The original Future is still running in the background; if it completes
  /// later its value will be stored in the cache for future calls.
  fallback,

  /// The deadline elapsed and the value was retrieved from the **internal
  /// smart cache** (a result stored by a previous successful call). 💾
  ///
  /// The cache entry may carry a TTL — check [DeadlineResult.resolvedAt] and
  /// your configured [DeadlineConfig.defaultCacheTtl] for freshness.
  cached,
}

// ─────────────────────────────────────────────────────────────────────────────
// DeadlineResult<T>
// ─────────────────────────────────────────────────────────────────────────────

/// An immutable container returned by [Future.withDeadline].
///
/// Carries the resolved [value] **plus** rich metadata that lets you answer:
/// - Did the Future beat the deadline?
/// - Is the data live, cached, or a static fallback?
/// - How long did the real Future actually take?
///
/// ### Pattern-matching example
///
/// ```dart
/// final result = await fetchData().withDeadline(
///   const Duration(seconds: 2),
///   fallback: defaultData,
///   cacheKey: 'my_data',
/// );
///
/// switch (result.source) {
///   case DeadlineResultSource.completed:
///     print('✅ Live data in ${result.actualDuration!.inMilliseconds}ms');
///   case DeadlineResultSource.cached:
///     print('💾 Cached data — refreshing in background');
///   case DeadlineResultSource.fallback:
///     print('🛡️  Static fallback — network may be slow');
/// }
/// ```
@immutable
final class DeadlineResult<T> {
  // ── Core payload ────────────────────────────────────────────────────────────

  /// The resolved value — always non-null when no exception is thrown.
  ///
  /// Originates from the original Future, the internal cache, or the caller's
  /// fallback, depending on [source].
  final T value;

  // ── Status flags ────────────────────────────────────────────────────────────

  /// `true` when the deadline elapsed before the original Future completed.
  ///
  /// A `true` value does **not** mean the call failed — it means the value
  /// was sourced from [cache] or [fallback] rather than the live Future.
  final bool isTimedOut;

  /// Indicates which tier of the fallback strategy provided [value].
  final DeadlineResultSource source;

  // ── Timing metadata ─────────────────────────────────────────────────────────

  /// Wall-clock duration from the moment [withDeadline] was called until the
  /// original Future completed.
  ///
  /// - `null` when [isTimedOut] is `true` and the original Future had not
  ///   finished before the deadline.
  /// - Non-null (and ≤ the deadline) when [source] is [DeadlineResultSource.completed].
  /// - May be non-null even when [isTimedOut] is `true` if the Future finished
  ///   after the deadline — in that case the value went to the cache, not
  ///   directly to the caller.
  final Duration? actualDuration;

  /// UTC timestamp of when this [DeadlineResult] was constructed.
  final DateTime resolvedAt;

  // ── Constructor ─────────────────────────────────────────────────────────────

  /// Creates a [DeadlineResult].
  ///
  /// Prefer using the factories exposed by `withDeadline()` rather than
  /// constructing this manually.
  const DeadlineResult({
    required this.value,
    required this.isTimedOut,
    required this.source,
    this.actualDuration,
    required this.resolvedAt,
  });

  // ── Convenience getters ─────────────────────────────────────────────────────

  /// `true` when [source] is [DeadlineResultSource.completed].
  ///
  /// Equivalent to `!isTimedOut` for the common case.
  bool get isLive => source == DeadlineResultSource.completed;

  /// `true` when the data came from the cache or the static fallback.
  ///
  /// Use this to show a "stale data" indicator in your UI without needing
  /// to inspect [source] directly.
  bool get isDegraded => !isLive;

  /// `true` when [source] is [DeadlineResultSource.cached].
  bool get isFromCache => source == DeadlineResultSource.cached;

  /// `true` when [source] is [DeadlineResultSource.fallback].
  bool get isFromFallback => source == DeadlineResultSource.fallback;

  // ── Object overrides ────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeadlineResult<T> &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          isTimedOut == other.isTimedOut &&
          source == other.source &&
          actualDuration == other.actualDuration &&
          resolvedAt == other.resolvedAt;

  @override
  int get hashCode => Object.hash(
        value,
        isTimedOut,
        source,
        actualDuration,
        resolvedAt,
      );

  @override
  String toString() => 'DeadlineResult<$T>('
      'value: $value, '
      'source: ${source.name}, '
      'timedOut: $isTimedOut, '
      'duration: ${actualDuration?.inMilliseconds}ms, '
      'resolvedAt: $resolvedAt'
      ')';

  /// Returns a copy with selected fields overridden — useful in tests.
  DeadlineResult<T> copyWith({
    T? value,
    bool? isTimedOut,
    DeadlineResultSource? source,
    Duration? actualDuration,
    DateTime? resolvedAt,
  }) {
    return DeadlineResult<T>(
      value: value ?? this.value,
      isTimedOut: isTimedOut ?? this.isTimedOut,
      source: source ?? this.source,
      actualDuration: actualDuration ?? this.actualDuration,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}
