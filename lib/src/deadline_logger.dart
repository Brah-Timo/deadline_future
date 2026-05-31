// ─────────────────────────────────────────────────────────────────────────────
// deadline_logger.dart  (internal — not exported from the barrel file)
//
// A lightweight, zero-dependency structured logger for the deadline_future
// package.  All output is gated behind [DeadlineLogLevel] so it can be
// completely silenced in production with a single line:
//
//   DeadlineConfig.logLevel = DeadlineLogLevel.silent;
// ─────────────────────────────────────────────────────────────────────────────

/// Controls how much information `deadline_future` prints to stdout.
///
/// Set via [DeadlineConfig.logLevel].
///
/// | Level    | What is printed                                     |
/// |----------|-----------------------------------------------------|
/// | verbose  | Every internal step (timers, cache hits/misses, …)  |
/// | info     | Deadline hits, fallback/cache decisions             |
/// | warning  | Degraded situations (no fallback, late errors, …)  |
/// | silent   | Nothing (default for production)                   |
enum DeadlineLogLevel {
  /// Most detailed — every internal step is logged.
  verbose,

  /// Deadline events and fallback/cache decisions.
  info,

  /// Only potentially problematic situations.
  warning,

  /// No output at all (production default).
  silent,
}

/// Internal structured logger used exclusively by `deadline_future`.
///
/// **Not part of the public API** — do not import this file directly.
/// Control output via [DeadlineConfig.logLevel].
abstract final class DeadlineLogger {
  // ── State ──────────────────────────────────────────────────────────────────
  static DeadlineLogLevel _level = DeadlineLogLevel.silent;

  // ── Internal setter (used by DeadlineConfig) ───────────────────────────────
  // ignore: avoid_setters_without_getters
  static set level(DeadlineLogLevel lvl) => _level = lvl;
  static DeadlineLogLevel get level => _level;

  // ── Log methods ────────────────────────────────────────────────────────────

  /// Emits a [DeadlineLogLevel.verbose] message.
  static void verbose(String message, {String? cacheKey, String? context}) {
    if (_level == DeadlineLogLevel.verbose) {
      _emit('VERBOSE', message, cacheKey: cacheKey, context: context);
    }
  }

  /// Emits a [DeadlineLogLevel.info] message.
  static void info(String message, {String? cacheKey, String? context}) {
    if (_level.index <= DeadlineLogLevel.info.index) {
      _emit('INFO   ', message, cacheKey: cacheKey, context: context);
    }
  }

  /// Emits a [DeadlineLogLevel.warning] message.
  static void warning(String message, {String? cacheKey, String? context}) {
    if (_level.index <= DeadlineLogLevel.warning.index) {
      _emit('WARNING', message, cacheKey: cacheKey, context: context);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static void _emit(
    String level,
    String message, {
    String? cacheKey,
    String? context,
  }) {
    final ts = DateTime.now().toIso8601String();
    final suffix = StringBuffer();
    if (cacheKey != null) suffix.write(' [key=$cacheKey]');
    if (context != null) suffix.write(' [ctx=$context]');

    // ignore: avoid_print
    print('[$ts][deadline_future][$level] $message$suffix');
  }
}
