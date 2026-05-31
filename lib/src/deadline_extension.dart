import 'dart:async';

import '../deadline_future.dart';
import 'deadline_cache.dart';
import 'deadline_config.dart';
import 'deadline_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// deadline_extension.dart
//
// The heart of the package.
//
// Architecture — "Completer Race" pattern:
//
//   withDeadline() creates ONE Completer<DeadlineResult<T>>.
//   Two async contestants race to call completer.complete():
//
//     • The original Future  — wins when it resolves before the deadline.
//     • A dart:async Timer   — wins when the deadline elapses first.
//
//   The second contestant to arrive finds `completer.isCompleted == true`
//   and exits silently.  If the late arrival is the *Future*, its value is
//   still written to the cache for future calls — turning every "loss" into
//   a future "win".
//
// Decision tree (executed by the Timer branch):
//
//   timeout hit
//       ├─ cacheKey set AND cache has valid entry  → return cached value
//       ├─ fallback != null                         → return fallback value
//       └─ neither                                  → throw DeadlineExceededException
//
// ─────────────────────────────────────────────────────────────────────────────

/// Core extension that adds deadline-aware resolution to any [Future<T>].
///
/// Import via the package barrel:
/// ```dart
/// import 'package:deadline_future/deadline_future.dart';
/// ```
extension DeadlineFutureExtension<T> on Future<T> {
  /// Resolves this [Future] within [deadline], falling back gracefully instead
  /// of crashing.
  ///
  /// Returns a [DeadlineResult<T>] that carries:
  /// - The resolved [value] (live, cached, or fallback).
  /// - [DeadlineResult.isTimedOut] — did the deadline elapse?
  /// - [DeadlineResult.source]    — where did the value come from?
  /// - [DeadlineResult.actualDuration] — how long did the original Future run?
  ///
  /// ---
  ///
  /// ### Parameters
  ///
  /// **[deadline]** *(required)*
  /// Maximum time to wait for the original Future.  Must be positive and
  /// non-zero; otherwise [InvalidDeadlineDurationException] is thrown
  /// synchronously before any async work begins.
  ///
  /// **[fallback]** *(optional)*
  /// A static value returned when the deadline elapses and no cached value
  /// exists.  Acts as the "last resort" safety net.
  ///
  /// **[cacheKey]** *(optional)*
  /// A unique string identifying this call site.  When supplied:
  /// - Successful results are stored under this key for future calls.
  /// - On timeout, a previously stored (and non-expired) value is returned
  ///   instead of the fallback.
  /// - Late-arriving results (after a timeout) are cached for the **next**
  ///   call, even though they are not returned this time.
  ///
  /// **[cacheTtl]** *(optional)*
  /// Per-call TTL for the cache entry.  Overrides
  /// [DeadlineConfig.defaultCacheTtl].  `null` means use the global default
  /// (which itself defaults to "never expire").
  ///
  /// **[onTimeout]** *(optional)*
  /// A zero-argument callback invoked synchronously the moment the deadline
  /// elapses — before the fallback/cache decision is made.  Use it to trigger
  /// UI updates, metrics, or logging at the call site.
  ///
  /// **[context]** *(optional)*
  /// A human-readable label for this call (e.g. `'BTC price widget'`).
  /// Appears in log messages and [DeadlineExceededException.context].
  ///
  /// ---
  ///
  /// ### Examples
  ///
  /// **Simple fallback:**
  /// ```dart
  /// final result = await fetchPrice().withDeadline(
  ///   const Duration(seconds: 2),
  ///   fallback: 65_000.0,
  /// );
  /// print(result.value); // always available
  /// ```
  ///
  /// **Smart cache:**
  /// ```dart
  /// // First call — Future wins, result stored in cache.
  /// final r1 = await fetchPrice().withDeadline(
  ///   const Duration(seconds: 2),
  ///   cacheKey: 'btc_price',
  ///   cacheTtl: const Duration(minutes: 5),
  /// );
  ///
  /// // Second call on a slow network — cache wins.
  /// final r2 = await fetchPrice().withDeadline(
  ///   const Duration(milliseconds: 200),
  ///   cacheKey: 'btc_price',
  /// );
  /// print(r2.source); // DeadlineResultSource.cached
  /// ```
  ///
  /// **UI indicator:**
  /// ```dart
  /// if (result.isDegraded) showStaleBadge();
  /// updateDisplay(result.value);
  /// ```
  ///
  /// ---
  ///
  /// ### Throws
  ///
  /// - [InvalidDeadlineDurationException] — synchronously, if [deadline] is
  ///   zero or negative.
  /// - [DeadlineExceededException] — asynchronously, if the deadline elapses
  ///   AND no cached value or [fallback] is available.
  /// - Any exception thrown by the original Future itself (propagated
  ///   unchanged when it occurs before the deadline).
  Future<DeadlineResult<T>> withDeadline(
    Duration deadline, {
    T? fallback,
    String? cacheKey,
    Duration? cacheTtl,
    void Function()? onTimeout,
    String? context,
  }) {
    // ── Guard: reject nonsensical deadlines immediately ──────────────────────
    if (deadline.isNegative || deadline == Duration.zero) {
      throw InvalidDeadlineDurationException(deadline);
    }

    return _resolveWithDeadline(
      future: this,
      deadline: deadline,
      fallback: fallback,
      cacheKey: cacheKey,
      cacheTtl: cacheTtl,
      onTimeout: onTimeout,
      context: context,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Core resolution logic (top-level function for cleaner stack traces)
// ─────────────────────────────────────────────────────────────────────────────

Future<DeadlineResult<T>> _resolveWithDeadline<T>({
  required Future<T> future,
  required Duration deadline,
  required T? fallback,
  required String? cacheKey,
  required Duration? cacheTtl,
  required void Function()? onTimeout,
  required String? context,
}) {
  final cache = DeadlineCache();
  final completer = Completer<DeadlineResult<T>>();
  final stopwatch = Stopwatch()..start();
  final effectiveTtl = cacheTtl ?? DeadlineConfig.defaultCacheTtl;
  final useCache = cacheKey != null && DeadlineConfig.enableGlobalCache;

  DeadlineLogger.verbose(
    'Starting — deadline=${deadline.inMilliseconds}ms',
    cacheKey: cacheKey,
    context: context,
  );

  // ── Timer branch — fires when the deadline elapses ───────────────────────
  final timer = Timer(deadline, () {
    if (completer.isCompleted) return; // Future already won the race.

    stopwatch.stop();
    onTimeout?.call();

    DeadlineLogger.info(
      'Deadline elapsed after ${deadline.inMilliseconds}ms',
      cacheKey: cacheKey,
      context: context,
    );

    // Tier 1 — try the smart cache first.
    if (useCache) {
      final key = cacheKey; // non-null: useCache = cacheKey != null && ...
      final cached = cache.retrieve<T>(key);
      if (cached != null) {
        DeadlineLogger.info(
          'Serving cached value',
          cacheKey: key,
          context: context,
        );
        completer.complete(
          DeadlineResult<T>(
            value: cached,
            isTimedOut: true,
            source: DeadlineResultSource.cached,
            resolvedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }
    }

    // Tier 2 — try the static fallback.
    if (fallback != null) {
      DeadlineLogger.info(
        'Serving static fallback',
        cacheKey: cacheKey,
        context: context,
      );
      completer.complete(
        DeadlineResult<T>(
          value: fallback,
          isTimedOut: true,
          source: DeadlineResultSource.fallback,
          resolvedAt: DateTime.now().toUtc(),
        ),
      );
      return;
    }

    // Tier 3 — nothing available, throw a descriptive exception.
    DeadlineLogger.warning(
      'No cache entry or fallback — throwing DeadlineExceededException',
      cacheKey: cacheKey,
      context: context,
    );
    completer.completeError(
      DeadlineExceededException(deadline: deadline, context: context),
      StackTrace.current,
    );
  });

  // ── Future branch — fires when the original Future completes ─────────────
  future.then((value) {
    timer.cancel(); // Future won — kill the timer.

    if (completer.isCompleted) {
      // Timer already resolved the completer (timeout occurred first).
      // The Future's result arrived late — cache it for the next call.
      if (useCache) {
        cache.store<T>(cacheKey, value, ttl: effectiveTtl);
        DeadlineLogger.verbose(
          'Late result stored in cache (not returned to caller)',
          cacheKey: cacheKey,
          context: context,
        );
      }
      return;
    }

    stopwatch.stop();

    // Store in cache so the next call benefits immediately.
    if (useCache) {
      cache.store<T>(cacheKey, value, ttl: effectiveTtl);
    }

    DeadlineLogger.verbose(
      'Future completed in ${stopwatch.elapsedMilliseconds}ms',
      cacheKey: cacheKey,
      context: context,
    );

    completer.complete(
      DeadlineResult<T>(
        value: value,
        isTimedOut: false,
        source: DeadlineResultSource.completed,
        actualDuration: stopwatch.elapsed,
        resolvedAt: DateTime.now().toUtc(),
      ),
    );
  }).catchError((Object error, StackTrace stackTrace) {
    timer.cancel();

    if (completer.isCompleted) {
      // Timeout already resolved — this is a late error.
      if (DeadlineConfig.ignoreErrorsAfterDeadline) {
        DeadlineLogger.warning(
          'Late error ignored (ignoreErrorsAfterDeadline=true): $error',
          cacheKey: cacheKey,
          context: context,
        );
        return;
      }
      // Re-surface the error in the current Zone if configured to do so.
      Zone.current.handleUncaughtError(error, stackTrace);
      return;
    }

    // Future failed before the timeout — propagate as-is.
    completer.completeError(error, stackTrace);
  });

  return completer.future;
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience extension — Duration shorthand on int
// ─────────────────────────────────────────────────────────────────────────────

/// Concise [Duration] constructors on [int].
///
/// Allows writing ergonomic deadline values:
/// ```dart
/// await fetch().withDeadline(3.seconds);
/// await fetch().withDeadline(500.milliseconds);
/// await fetch().withDeadline(2.minutes);
/// ```
extension DeadlineDuration on int {
  /// Creates a [Duration] of this many milliseconds.
  Duration get milliseconds => Duration(milliseconds: this);

  /// Creates a [Duration] of this many seconds.
  Duration get seconds => Duration(seconds: this);

  /// Creates a [Duration] of this many minutes.
  Duration get minutes => Duration(minutes: this);

  /// Creates a [Duration] of this many hours.
  Duration get hours => Duration(hours: this);
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch convenience extension — operate on a list of Futures
// ─────────────────────────────────────────────────────────────────────────────

/// Applies [withDeadline] to every element of a [List<Future<T>>] with a
/// **shared** deadline and configuration.
///
/// All Futures run concurrently (no sequential waiting).  Each element
/// independently races against the same [deadline].
///
/// ```dart
/// final prices = await [
///   fetchBtc(),
///   fetchEth(),
///   fetchSol(),
/// ].withDeadlineAll(
///   const Duration(seconds: 2),
///   fallback: 0.0,
/// );
///
/// for (final r in prices) {
///   print('${r.value} — ${r.source.name}');
/// }
/// ```
extension DeadlineFutureListExtension<T> on List<Future<T>> {
  /// Resolves all Futures with a shared [deadline].
  ///
  /// [fallback], [cacheTtl], and [onTimeout] are applied to **every** element.
  /// [cacheKeys] must either be `null` (no caching) or have the same length
  /// as the list.
  Future<List<DeadlineResult<T>>> withDeadlineAll(
    Duration deadline, {
    T? fallback,
    List<String>? cacheKeys,
    Duration? cacheTtl,
    void Function(int index)? onTimeout,
    String? context,
  }) async {
    assert(
      cacheKeys == null || cacheKeys.length == length,
      'cacheKeys length (${cacheKeys.length}) '
      'must match the list length ($length)',
    );

    return Future.wait([
      for (var i = 0; i < length; i++)
        this[i].withDeadline(
          deadline,
          fallback: fallback,
          cacheKey: cacheKeys?[i],
          cacheTtl: cacheTtl,
          onTimeout: onTimeout == null ? null : () => onTimeout(i),
          context: context != null ? '$context[$i]' : null,
        ),
    ]);
  }
}
