# Getting Started with `deadline_future`

## Why does this package exist?

Dart's built-in `Future.timeout()` gives you two options:

| Scenario | Outcome |
|---|---|
| Future completes before timeout | ✅ You get the value |
| Future too slow, `onTimeout` provided | ✅ You get `onTimeout()` value |
| Future too slow, no `onTimeout` | ❌ `TimeoutException` crash |
| Future completes *after* the timeout | 🗑️ Result silently discarded forever |

The last two rows are the problem.  In real-time apps — stock tickers, chat
heads, live dashboards — you often want:

> *"Give me the freshest data you have within N ms. If you can't, give me
>  whatever you had last time. Don't crash."*

`deadline_future` provides that third path.

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  deadline_future: ^0.1.0
```

```bash
dart pub get
```

---

## The three-tier resolution strategy

Every call to `withDeadline()` resolves through this decision tree:

```
Future completes before deadline?
  └─ YES → return live result  [DeadlineResultSource.completed]
  └─ NO  → is there a valid cache entry for cacheKey?
              └─ YES → return cached value  [DeadlineResultSource.cached]
              └─ NO  → is fallback != null?
                          └─ YES → return fallback  [DeadlineResultSource.fallback]
                          └─ NO  → throw DeadlineExceededException
```

You decide how many safety nets to set up — from zero (pure exception) to two
(cache + fallback).

---

## Step 1 — Minimal usage (static fallback only)

```dart
import 'package:deadline_future/deadline_future.dart';

final result = await fetchUserProfile().withDeadline(
  const Duration(seconds: 2),
  fallback: UserProfile.guest(),
);

print(result.value.name);
```

`result` is always non-null.  `result.isTimedOut` tells you whether the
deadline was hit.

---

## Step 2 — Add the smart cache

The cache remembers the last successful result for a given key and serves it
automatically on the next timeout.

```dart
// Call 1 (fast network) — result is stored in cache.
final r1 = await fetchBtcPrice().withDeadline(
  const Duration(seconds: 2),
  cacheKey: 'btc_price',
  cacheTtl: const Duration(minutes: 5),
);

// Call 2 (slow network) — cache kicks in.
final r2 = await fetchBtcPrice().withDeadline(
  const Duration(milliseconds: 300),
  cacheKey: 'btc_price',
  fallback: 0.0,           // last-resort if cache is also empty
);

if (r2.source == DeadlineResultSource.cached) {
  showStaleBadge();        // let the user know data isn't live
}
```

### Self-healing property

Even if call 2 times out *before* the new Future finishes, the Future keeps
running in the background.  When it eventually completes, its value is written
to the cache — so call 3 will benefit from a fresh cached value.

---

## Step 3 — Read the result metadata

```dart
switch (result.source) {
  case DeadlineResultSource.completed:
    print('Live ✅  (${result.actualDuration!.inMilliseconds}ms)');
  case DeadlineResultSource.cached:
    print('Cached 💾');
  case DeadlineResultSource.fallback:
    print('Fallback 🛡️');
}

// Or use the bool helpers:
if (result.isDegraded) showRefreshButton();
```

---

## Step 4 — onTimeout callback

```dart
await fetchData().withDeadline(
  const Duration(seconds: 1),
  fallback: defaultData,
  onTimeout: () {
    analytics.track('deadline_hit', {'feature': 'price_widget'});
    showSpinner(false);
  },
);
```

---

## Step 5 — Duration shorthand

```dart
// Instead of const Duration(seconds: 3):
await fetchData().withDeadline(3.seconds, fallback: defaults);

// Or:
await fetchData().withDeadline(500.milliseconds, fallback: defaults);
```

---

## Step 6 — Batch concurrent calls

```dart
final results = await [
  fetchBtc(),
  fetchEth(),
  fetchSol(),
].withDeadlineAll(
  const Duration(milliseconds: 500),
  cacheKeys: ['btc', 'eth', 'sol'],
  fallback: 0.0,
  onTimeout: (i) => print('Feed $i timed out'),
);
```

All three Futures run concurrently.  Each one independently races against the
same deadline.

---

## Step 7 — Global configuration (call once at app start)

```dart
void main() {
  // Enable/configure caching globally.
  DeadlineConfig.enableGlobalCache  = true;
  DeadlineConfig.defaultCacheTtl    = const Duration(minutes: 10);
  DeadlineConfig.maxCacheEntries    = 500;

  // Log deadline events in debug builds, silent in production.
  DeadlineConfig.logLevel = kDebugMode
      ? DeadlineLogLevel.info
      : DeadlineLogLevel.silent;

  runApp(const MyApp());
}
```

---

## Exception reference

| Exception | When | Prevention |
|---|---|---|
| `InvalidDeadlineDurationException` | `deadline` is zero or negative | Always pass a positive `Duration` |
| `DeadlineExceededException` | Deadline elapsed, no cache, no fallback | Provide `fallback:` and/or `cacheKey:` |

---

## FAQ

**Q: Does `withDeadline` cancel the original Future?**  
A: No — Dart does not support Future cancellation. The original Future
continues running. If it completes after the deadline its result is silently
stored in the cache (if `cacheKey` was provided), improving future calls.

**Q: Is the cache shared across isolates?**  
A: No. `DeadlineCache` is a process-scoped singleton. Each isolate has its own
instance.

**Q: Can I use this in Flutter?**  
A: Absolutely — `deadline_future` is pure Dart with no Flutter dependency.

**Q: Is there overhead compared to `Future.timeout`?**  
A: Minimal. The `Completer` + `Timer` pattern has the same O(1) complexity as
`Future.timeout`. See `benchmark/throughput_bench.dart` for measured numbers.

**Q: How do I reset the cache between tests?**  
A: Call `DeadlineConfig.reset()` in `setUp()`. This clears all config fields
and the cache in one call.
