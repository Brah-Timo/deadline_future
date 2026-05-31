# Changelog

All notable changes to `deadline_future` are documented in this file.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).  
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.1.0] — 2026-05-29

### 🎉 Initial Release

#### Added

**Core API**
- `Future<T>.withDeadline(Duration, {...})` extension — the primary entry point.
  Resolves any `Future<T>` with a configurable deadline and a three-tier
  fallback strategy (live → cached → static fallback → exception).
- `DeadlineResult<T>` — immutable result container carrying:
  - `value` — the resolved value (live, cached, or fallback).
  - `isTimedOut` — whether the deadline elapsed.
  - `source` (`DeadlineResultSource`) — `completed`, `cached`, or `fallback`.
  - `actualDuration` — how long the original Future ran.
  - `resolvedAt` — UTC timestamp of resolution.
  - Convenience getters: `isLive`, `isDegraded`, `isFromCache`, `isFromFallback`.
  - `copyWith()` for non-destructive mutation (useful in tests).

**Smart Cache**
- `DeadlineCache` — internal in-memory LRU cache with:
  - Per-entry TTL support (`cacheTtl` parameter per call).
  - Global default TTL (`DeadlineConfig.defaultCacheTtl`).
  - Configurable capacity with FIFO eviction (`maxEntries`, default 200).
  - Lazy TTL eviction on `retrieve()`.
  - `purgeExpired()` for eager eviction.
  - Self-healing behaviour: late-arriving Futures (after timeout) are
    automatically stored in the cache for the next call.

**Exception Hierarchy**
- `DeadlineFutureException` — sealed base class for all package exceptions.
- `DeadlineExceededException` — thrown when deadline elapses with no cache
  entry or fallback available. Carries `deadline`, `context`, `occurredAt`.
- `InvalidDeadlineDurationException` — thrown synchronously for zero or
  negative `deadline` values.
- `DeadlineCacheException` — defensive exception for cache I/O failures
  (reserved for future persistent-cache backends).

**Global Configuration**
- `DeadlineConfig` — static configuration hub:
  - `enableGlobalCache` (default `true`)
  - `defaultCacheTtl` (default `null` = never expire)
  - `maxCacheEntries` (default `200`)
  - `ignoreErrorsAfterDeadline` (default `true`)
  - `logLevel` (`DeadlineLogLevel.silent` by default)
  - `reset()` — restores all defaults and clears the cache.
  - `clearCache()`, `evictCacheEntry(key)`, `cacheSize` — cache helpers.

**Logging**
- `DeadlineLogger` — internal structured logger (not exported publicly).
- `DeadlineLogLevel` enum: `verbose`, `info`, `warning`, `silent`.
- All log output is gated — zero cost when `logLevel = silent`.

**Ergonomic Extras**
- `DeadlineDuration` extension on `int`:
  - `3.seconds`, `500.milliseconds`, `2.minutes`, `1.hours`
- `DeadlineFutureListExtension<T>` on `List<Future<T>>`:
  - `.withDeadlineAll(deadline, {...})` — concurrent batch resolution with
    shared deadline, per-element `cacheKeys`, and `onTimeout(index)` callback.

**Tests**
- Unit tests for `DeadlineResult` (construction, equality, copyWith, toString).
- Unit tests for `DeadlineCache` + `DeadlineConfig` (TTL, eviction, reset).
- Unit tests for `DeadlineFutureExtension` (all paths, callbacks, exceptions,
  batch extension, Duration shorthand).
- Integration tests covering: crypto price feed, chat, live dashboard batch,
  retry pattern, and self-healing cache scenarios.

**Developer Experience**
- Zero runtime dependencies (only `meta: ^1.9.0` for `@immutable`).
- Strict analysis options with `strict-casts`, `strict-inference`,
  `strict-raw-types` enabled.
- `example/main.dart` with 10 annotated real-world examples.
- `benchmark/throughput_bench.dart` comparing against `Future.timeout`.
- `doc/getting_started.md` — step-by-step guide.
- BSD-3-Clause license.

---

## [Unreleased]

### Planned
- Persistent cache backend (Hive / shared_preferences adapter).
- `withRetryDeadline()` — built-in retry loop with per-attempt deadlines.
- `DeadlineStream` — stream variant (`Stream<T>.withDeadline()`).
- `DeadlineResult.when()` — exhaustive pattern-matching helper.
- Web-compatible timer isolation for Flutter Web.
- Coverage badge integration (Coveralls / Codecov).
