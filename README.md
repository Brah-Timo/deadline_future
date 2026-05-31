# deadline_future 🏁

[![pub.dev](https://img.shields.io/pub/v/deadline_future.svg)](https://pub.dev/packages/deadline_future)
[![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.0.0-blue)](https://dart.dev)
[![License: BSD-3](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![style: lints](https://img.shields.io/badge/style-lints-4BC0F5.svg)](https://pub.dev/packages/lints)

> **A time-bounded Future that never throws `TimeoutException`.**  
> Returns the freshest data available — live, cached, or a static fallback —
> instead of crashing.

---

## The Problem

```dart
// ❌ Dart's built-in Future.timeout — "all or nothing"
try {
  final price = await fetchPrice().timeout(const Duration(seconds: 2));
} on TimeoutException {
  // The result was discarded even if it arrived 1ms later.
  // You must handle the exception every single time.
}
```

In real-time apps this is painful: every slow network spike crashes the UI,
every late response is wasted, and you have no visibility into *why* the
fallback was used.

---

## The Solution

```dart
// ✅ deadline_future — three-tier graceful fallback
final result = await fetchPrice().withDeadline(
  const Duration(seconds: 2),
  fallback: lastKnownPrice,      // 🛡️ tier 3: static safety net
  cacheKey: 'btc_price',         // 💾 tier 2: automatic smart cache
  cacheTtl: const Duration(minutes: 5),
  onTimeout: () => showSpinner(), // called the moment deadline hits
  context: 'BTC price widget',   // appears in logs & exceptions
);

// result is ALWAYS available — never null, never an exception
switch (result.source) {
  case DeadlineResultSource.completed:
    print('✅ Live  — ${result.actualDuration!.inMilliseconds}ms');
  case DeadlineResultSource.cached:
    print('💾 Cached — showing last known value');
  case DeadlineResultSource.fallback:
    print('🛡️  Fallback — network is struggling');
}

if (result.isDegraded) showStaleBadge(); // one-liner UI indicator
updatePrice(result.value);               // always works
```

---

## Resolution Strategy

```
withDeadline(deadline, fallback: F, cacheKey: K)
          │
          ├─ Future completes in time?      → ✅ live result
          │                                    (stored in cache for next time)
          │
          ├─ Timeout + cache[K] valid?      → 💾 cached result
          │
          ├─ Timeout + F != null?           → 🛡️  fallback result
          │
          └─ Timeout + nothing available?   → 🔴 DeadlineExceededException
```

> **Self-healing cache:** even after a timeout, the original Future keeps
> running. When it finally completes, its value is stored in the cache —
> automatically improving the **next** call.

---

## Installation

```yaml
dependencies:
  deadline_future: ^0.1.0
```

```bash
dart pub get
```

---

## Quick-start Recipes

### Minimal — static fallback only

```dart
final result = await fetchUserProfile().withDeadline(
  const Duration(seconds: 2),
  fallback: UserProfile.guest(),
);
print(result.value.displayName); // always available
```

### Smart cache — best for repeated calls

```dart
// First call: Future wins → cached.
await fetchBtcPrice().withDeadline(
  const Duration(seconds: 2),
  cacheKey: 'btc',
  cacheTtl: const Duration(minutes: 5),
);

// Second call: network degraded → served from cache.
final r = await fetchBtcPrice().withDeadline(
  const Duration(milliseconds: 300),
  cacheKey: 'btc',
  fallback: 0.0,
);
```

### Duration shorthand

```dart
// Clean, readable deadlines:
await fetch().withDeadline(3.seconds);
await fetch().withDeadline(500.milliseconds);
await fetch().withDeadline(2.minutes);
```

### Batch concurrent calls

```dart
final results = await [fetchBtc(), fetchEth(), fetchSol()]
    .withDeadlineAll(
      const Duration(milliseconds: 500),
      cacheKeys: ['btc', 'eth', 'sol'],
      fallback: 0.0,
      onTimeout: (i) => print('Feed $i timed out'),
    );
```

### Exception handling

```dart
try {
  await myFuture.withDeadline(const Duration(seconds: 1));
} on DeadlineExceededException catch (e) {
  // Only thrown when NO cache entry AND NO fallback exist.
  print('Exceeded ${e.deadline.inMilliseconds}ms — ${e.context}');
} on InvalidDeadlineDurationException {
  // Synchronous guard against Duration.zero / negative values.
}
```

### Global configuration (app startup)

```dart
void main() {
  DeadlineConfig.enableGlobalCache = true;
  DeadlineConfig.defaultCacheTtl   = const Duration(minutes: 10);
  DeadlineConfig.maxCacheEntries   = 500;
  DeadlineConfig.logLevel          = kDebugMode
      ? DeadlineLogLevel.info
      : DeadlineLogLevel.silent;
  runApp(const MyApp());
}
```

---

## API Reference

### `Future<T>.withDeadline()`

| Parameter | Type | Required | Description |
|---|---|---|---|
| `deadline` | `Duration` | ✅ | Max wait time. Must be positive. |
| `fallback` | `T?` | | Static value returned on timeout (if cache miss). |
| `cacheKey` | `String?` | | Enables smart cache. Unique per call site. |
| `cacheTtl` | `Duration?` | | Per-call TTL. Overrides `defaultCacheTtl`. |
| `onTimeout` | `void Function()?` | | Called the instant the deadline elapses. |
| `context` | `String?` | | Label for logs and exception messages. |

**Returns:** `Future<DeadlineResult<T>>`

---

### `DeadlineResult<T>`

| Member | Type | Description |
|---|---|---|
| `value` | `T` | The resolved value. |
| `isTimedOut` | `bool` | Did the deadline elapse? |
| `source` | `DeadlineResultSource` | `completed`, `cached`, or `fallback`. |
| `isLive` | `bool` | Shorthand: `source == completed`. |
| `isDegraded` | `bool` | Shorthand: `!isLive`. |
| `isFromCache` | `bool` | Shorthand: `source == cached`. |
| `isFromFallback` | `bool` | Shorthand: `source == fallback`. |
| `actualDuration` | `Duration?` | How long the original Future took. |
| `resolvedAt` | `DateTime` | UTC timestamp of resolution. |
| `copyWith(...)` | `DeadlineResult<T>` | Non-destructive field override. |

---

### `DeadlineConfig` (static)

| Property / Method | Default | Description |
|---|---|---|
| `enableGlobalCache` | `true` | Master cache toggle. |
| `defaultCacheTtl` | `null` | Default TTL for all cache entries. |
| `maxCacheEntries` | `200` | Cache capacity before FIFO eviction. |
| `ignoreErrorsAfterDeadline` | `true` | Swallow late Future errors. |
| `logLevel` | `silent` | Controls stdout diagnostic output. |
| `reset()` | — | Restores defaults + clears cache. |
| `clearCache()` | — | Empties the cache only. |
| `evictCacheEntry(key)` | — | Removes one entry by key. |
| `cacheSize` | — | Current number of live cache entries. |

---

## Comparison Table

| Feature | `Future.timeout()` | `withDeadline()` |
|---|---|---|
| Future completes in time | ✅ Value | ✅ Value + metadata |
| Timeout with handler | ✅ `onTimeout` value | ✅ Fallback / cache |
| Timeout without handler | ❌ `TimeoutException` | 🔶 `DeadlineExceededException`\* |
| Late result | 🗑️ Discarded | 💾 Cached for next call |
| Next call after timeout | ❌ Crashes again | ✅ Served from cache |
| Result metadata | ❌ None | ✅ `DeadlineResultSource` |
| `onTimeout` callback | ❌ | ✅ |
| Global config | ❌ | ✅ `DeadlineConfig` |
| Batch API | ❌ | ✅ `withDeadlineAll` |
| Duration shorthand | ❌ | ✅ `3.seconds` |

\* Only thrown as a last resort — cache and fallback are checked first.

---

## Ideal Use Cases

- 📈 **Crypto / stock price feeds** — show last known price while refreshing
- 💬 **Chat heads** — display cached messages while server is slow
- 📊 **Live dashboards** — partial data is better than blank panels
- 🏟️ **Sports scores** — stale score with "updating..." badge
- 🔄 **Retry wrappers** — compose with `withDeadline` for per-attempt limits
- 🌐 **Any API call** where "stale but available" beats "fresh but crashed"

---

## Testing

```bash
dart test
```

Run the examples:
```bash
dart run example/main.dart
```

Run the benchmarks:
```bash
dart run benchmark/throughput_bench.dart
```

---

## License

[BSD-3-Clause](LICENSE) © 2026 deadline_future contributors
