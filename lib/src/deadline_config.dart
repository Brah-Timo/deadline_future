import 'deadline_cache.dart';
import 'deadline_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// deadline_config.dart
//
// A single, app-wide configuration hub for the deadline_future package.
// Call these setters once at app startup (e.g. in main()) and every subsequent
// call to withDeadline() will respect them automatically.
// ─────────────────────────────────────────────────────────────────────────────

// Re-export DeadlineLogLevel so consumers only need to import the barrel file.
export 'deadline_logger.dart' show DeadlineLogLevel;

/// Global configuration for the `deadline_future` package.
///
/// All properties are static so there is no need to pass a config object
/// around — just set them once at app startup:
///
/// ```dart
/// void main() {
///   // Enable caching, set a 5-minute default TTL, verbose logging in debug.
///   DeadlineConfig.enableGlobalCache  = true;
///   DeadlineConfig.defaultCacheTtl    = const Duration(minutes: 5);
///   DeadlineConfig.maxCacheEntries    = 500;
///   DeadlineConfig.logLevel           = kDebugMode
///       ? DeadlineLogLevel.info
///       : DeadlineLogLevel.silent;
///
///   runApp(const MyApp());
/// }
/// ```
abstract final class DeadlineConfig {
  DeadlineConfig._();

  // ── Cache ─────────────────────────────────────────────────────────────────

  /// Whether the internal [DeadlineCache] is active.
  ///
  /// When `true` (default), any [withDeadline] call that supplies a
  /// `cacheKey` will automatically:
  /// - **Store** the result on success.
  /// - **Return** the cached value on timeout (if available and not expired).
  /// - **Store** late-arriving results even after a timeout.
  ///
  /// Set to `false` to disable caching globally (useful in tests or when
  /// you want purely stateless behaviour).
  ///
  /// Defaults to `true`.
  static bool enableGlobalCache = true;

  /// Default time-to-live applied to every cache entry when the individual
  /// `cacheTtl` parameter of [withDeadline] is not provided.
  ///
  /// `null` (default) means entries never expire — they are kept until
  /// manually [DeadlineCache.evict]ed, [DeadlineCache.clear]ed, or evicted
  /// because the cache reached [maxCacheEntries].
  ///
  /// Example — expire cached prices every 10 minutes:
  /// ```dart
  /// DeadlineConfig.defaultCacheTtl = const Duration(minutes: 10);
  /// ```
  static Duration? defaultCacheTtl;

  /// Maximum number of entries the internal cache may hold simultaneously.
  ///
  /// When this limit is reached the **oldest** entry is evicted before a new
  /// one is stored (FIFO policy).
  ///
  /// Propagates immediately to [DeadlineCache.maxEntries].
  ///
  /// Defaults to `200`.
  static int get maxCacheEntries => DeadlineCache.maxEntries;
  static set maxCacheEntries(int value) {
    assert(value > 0, 'maxCacheEntries must be positive');
    DeadlineCache.maxEntries = value;
  }

  // ── Error handling ────────────────────────────────────────────────────────

  /// Whether errors emitted by the original Future **after** the deadline
  /// has already been resolved are silently ignored.
  ///
  /// When `true` (default): a late error is dropped on the floor. The caller
  /// already received a result (cached/fallback), so the error is irrelevant.
  ///
  /// When `false`: a late error is re-thrown from an unawaited Future context
  /// (it will surface as an unhandled error in the current [Zone]).
  ///
  /// **Recommendation**: keep this `true` in production to avoid spurious
  /// error logs from network race conditions.
  static bool ignoreErrorsAfterDeadline = true;

  // ── Logging ───────────────────────────────────────────────────────────────

  /// Controls how much diagnostic output `deadline_future` produces.
  ///
  /// | Level   | Recommended environment |
  /// |---------|-------------------------|
  /// | verbose | Unit / integration tests |
  /// | info    | Development / debug builds |
  /// | warning | Staging |
  /// | silent  | Production (default) |
  ///
  /// See [DeadlineLogLevel] for details.
  static DeadlineLogLevel get logLevel => DeadlineLogger.level;
  static set logLevel(DeadlineLogLevel level) {
    DeadlineLogger.level = level;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Resets **all** configuration fields to their default values and clears
  /// the internal cache.
  ///
  /// Primarily intended for use between test cases to guarantee isolation:
  ///
  /// ```dart
  /// setUp(() => DeadlineConfig.reset());
  /// ```
  static void reset() {
    enableGlobalCache = true;
    defaultCacheTtl = null;
    DeadlineCache.maxEntries = 200;
    ignoreErrorsAfterDeadline = true;
    DeadlineLogger.level = DeadlineLogLevel.silent;
    DeadlineCache().clear();
  }

  // ── Cache helpers (pass-through convenience) ──────────────────────────────

  /// Clears the entire internal cache without touching other config.
  static void clearCache() => DeadlineCache().clear();

  /// Evicts a single entry from the cache by [key].
  static void evictCacheEntry(String key) => DeadlineCache().evict(key);

  /// Returns the current number of live (non-expired) cache entries.
  static int get cacheSize => DeadlineCache().size;
}
