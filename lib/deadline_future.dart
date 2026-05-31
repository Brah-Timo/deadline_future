/// `deadline_future` — Graceful deadline handling for Dart Futures.
///
/// Instead of crashing with [TimeoutException], this package provides a
/// three-tier fallback strategy:
///
/// 1. **Live result** — Future completed before the deadline. ✅
/// 2. **Cached result** — Timeout hit, but a previous successful value is
///    available in the built-in smart cache. 💾
/// 3. **Static fallback** — Timeout hit, cache empty, use a user-supplied
///    default value. 🛡️
///
/// If none of the above apply, a [DeadlineExceededException] is thrown —
/// never a raw [TimeoutException].
///
/// ## Quick start
///
/// ```dart
/// import 'package:deadline_future/deadline_future.dart';
///
/// final result = await fetchBtcPrice().withDeadline(
///   const Duration(seconds: 2),
///   fallback: 65_000.0,
///   cacheKey: 'btc_price',
///   cacheTtl: const Duration(minutes: 5),
///   onTimeout: () => print('⚠️  deadline hit — using fallback/cache'),
///   context: 'BTC price widget',
/// );
///
/// if (result.isDegraded) {
///   showStaleIndicator();   // data came from cache or fallback
/// }
/// displayPrice(result.value); // always has a value — never crashes
/// ```
///
/// ## Global configuration (call once at app start)
///
/// ```dart
/// DeadlineConfig.enableGlobalCache = true;
/// DeadlineConfig.defaultCacheTtl  = const Duration(minutes: 10);
/// DeadlineConfig.logLevel          = DeadlineLogLevel.info;
/// ```
library deadline_future;

// ── Public API surface ────────────────────────────────────────────────────────
export 'src/deadline_extension.dart';
export 'src/deadline_result.dart';
export 'src/deadline_config.dart';
export 'src/exceptions/deadline_exception.dart';

// ── Internal files intentionally NOT exported ─────────────────────────────────
// src/deadline_cache.dart   — internal smart cache (singleton)
// src/deadline_logger.dart  — internal structured logger
