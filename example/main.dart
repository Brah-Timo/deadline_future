// ignore_for_file: avoid_print

/// deadline_future — comprehensive usage examples
///
/// Run with:
///   dart run example/main.dart
library;

import 'dart:async';

import 'package:deadline_future/deadline_future.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Fake API helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<double> fetchBtcPrice({int latencyMs = 800}) async {
  await Future<void>.delayed(Duration(milliseconds: latencyMs));
  return 67432.50;
}

Future<String> fetchChatMessages(String roomId, {int latencyMs = 100}) async {
  await Future<void>.delayed(Duration(milliseconds: latencyMs));
  return 'Latest messages from $roomId';
}

Future<Map<String, double>> fetchPortfolio({int latencyMs = 200}) async {
  await Future<void>.delayed(Duration(milliseconds: latencyMs));
  return {'BTC': 1.5, 'ETH': 10.0, 'SOL': 250.0};
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 1 — Simple static fallback
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example1_simpleFallback() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 1: Simple Static Fallback               ║');
  print('╚══════════════════════════════════════════════════╝');

  // API takes 800ms but our deadline is 300ms → fallback fires.
  final result = await fetchBtcPrice(latencyMs: 800).withDeadline(
    const Duration(milliseconds: 300),
    fallback: 66000.0,
    context: 'BTC price widget',
    onTimeout: () => print('  ⚠️  Deadline hit — using static fallback'),
  );

  print('  Price   : \$${result.value}');
  print('  Source  : ${result.source.name}');
  print('  TimedOut: ${result.isTimedOut}');
  // Expected → Source: fallback
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 2 — Smart cache across multiple calls
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example2_smartCache() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 2: Smart Cache                          ║');
  print('╚══════════════════════════════════════════════════╝');

  // Call 1 — fast network, result is cached.
  final r1 = await fetchBtcPrice(latencyMs: 100).withDeadline(
    const Duration(milliseconds: 500),
    cacheKey: 'btc_price',
    cacheTtl: const Duration(minutes: 5),
  );
  print('  Call 1 → \$${r1.value}  [${r1.source.name}]'
      '  (${r1.actualDuration?.inMilliseconds}ms)');

  // Call 2 — slow network → served from cache instead of waiting.
  final r2 = await fetchBtcPrice(latencyMs: 2000).withDeadline(
    const Duration(milliseconds: 150),
    cacheKey: 'btc_price',
    fallback: 50000.0,
    onTimeout: () => print('  💾  Serving from cache'),
  );
  print('  Call 2 → \$${r2.value}  [${r2.source.name}]');
  // Expected Call 2 → Source: cached
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 3 — isDegraded for UI indicators
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example3_uiIndicator() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 3: isDegraded for UI Badge              ║');
  print('╚══════════════════════════════════════════════════╝');

  final result = await fetchBtcPrice(latencyMs: 1500).withDeadline(
    const Duration(milliseconds: 300),
    fallback: 65000.0,
  );

  if (result.isDegraded) {
    // Show a "stale data" indicator in your widget.
    print('  🟡 Approximate price: \$${result.value}  ← tap to refresh');
  } else {
    print('  🟢 Live price: \$${result.value}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 4 — pattern matching on source
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example4_patternMatching() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 4: Pattern-matching on source           ║');
  print('╚══════════════════════════════════════════════════╝');

  final result = await fetchBtcPrice(latencyMs: 80).withDeadline(
    const Duration(milliseconds: 500),
    cacheKey: 'btc_pattern',
  );

  switch (result.source) {
    case DeadlineResultSource.completed:
      print('  ✅ Live — fetched in ${result.actualDuration!.inMilliseconds}ms');
    case DeadlineResultSource.cached:
      print('  💾 Cached — refreshing in background');
    case DeadlineResultSource.fallback:
      print('  🛡️  Static fallback — check network');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 5 — Duration shorthand sugar
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example5_durationSugar() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 5: Duration Shorthand                   ║');
  print('╚══════════════════════════════════════════════════╝');

  // Use the DeadlineDuration extension for clean, readable deadlines.
  final result = await fetchBtcPrice(latencyMs: 50).withDeadline(
    2.seconds, // ← clean!
    fallback: 0.0,
  );

  print('  Result: \$${result.value}  (deadline: 2 seconds)');
  print('  Source: ${result.source.name}');
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 6 — Batch: fetch multiple feeds concurrently
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example6_batchFeed() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 6: Concurrent Batch Feed                ║');
  print('╚══════════════════════════════════════════════════╝');

  final symbols = ['BTC', 'ETH', 'SOL'];
  final latencies = [80, 250, 400]; // mixed latencies

  final futures = List.generate(
    symbols.length,
    (i) => Future<double>.delayed(
      Duration(milliseconds: latencies[i]),
      () => [67000.0, 3500.0, 180.0][i],
    ),
  );

  final results = await futures.withDeadlineAll(
    const Duration(milliseconds: 200), // SOL will time out
    cacheKeys: symbols,
    fallback: 0.0,
    onTimeout: (i) => print('  ⚠️  ${symbols[i]} timed out'),
  );

  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    final icon = r.isLive ? '🟢' : '🟡';
    print('  $icon ${symbols[i]}: \$${r.value}  [${r.source.name}]');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 7 — Chat with stale message fallback
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example7_chat() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 7: Chat — Stale Message Fallback        ║');
  print('╚══════════════════════════════════════════════════╝');

  const roomId = 'general';
  const cacheKey = 'chat_$roomId';

  // First load — fast, result cached.
  final first = await fetchChatMessages(roomId, latencyMs: 60).withDeadline(
    const Duration(milliseconds: 500),
    cacheKey: cacheKey,
  );
  print('  First load  : "${first.value}"  [${first.source.name}]');

  // Second load — server is slow → stale from cache.
  final second = await fetchChatMessages(roomId, latencyMs: 2000).withDeadline(
    const Duration(milliseconds: 100),
    cacheKey: cacheKey,
    fallback: '(offline)',
    onTimeout: () => print('  ℹ️  Showing cached messages while refreshing...'),
  );
  print('  Second load : "${second.value}"  [${second.source.name}]');
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 8 — Global config + verbose logging
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example8_globalConfig() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 8: Global Config + Logging              ║');
  print('╚══════════════════════════════════════════════════╝');

  DeadlineConfig.enableGlobalCache = true;
  DeadlineConfig.defaultCacheTtl = const Duration(minutes: 10);
  DeadlineConfig.maxCacheEntries = 500;
  DeadlineConfig.logLevel = DeadlineLogLevel.info; // prints INFO lines below

  final result = await fetchBtcPrice(latencyMs: 1000).withDeadline(
    const Duration(milliseconds: 200),
    fallback: 64000.0,
    context: 'example8',
  );

  print('  Value: \$${result.value}  [${result.source.name}]');
  print('  Cache size after call: ${DeadlineConfig.cacheSize}');

  // Restore to defaults.
  DeadlineConfig.reset();
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 9 — DeadlineExceededException handling
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example9_exceptionHandling() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 9: Exception Handling                   ║');
  print('╚══════════════════════════════════════════════════╝');

  try {
    await fetchBtcPrice(latencyMs: 2000).withDeadline(
      const Duration(milliseconds: 50),
      // No fallback and no cacheKey → DeadlineExceededException
      context: 'no_safety_net',
    );
  } on DeadlineExceededException catch (e) {
    print('  🔴 Caught: ${e.runtimeType}');
    print('  Deadline : ${e.deadline.inMilliseconds}ms');
    print('  Context  : ${e.context}');
    print('  Message  : ${e.message}');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Example 10 — Late-arriving result self-heals the cache
// ─────────────────────────────────────────────────────────────────────────────

Future<void> example10_lateArrivalHealsCache() async {
  print('\n╔══════════════════════════════════════════════════╗');
  print('║  Example 10: Late Result Self-heals Cache        ║');
  print('╚══════════════════════════════════════════════════╝');

  const key = 'self_heal';

  // Call A: deadline too tight → fallback returned, but the real Future
  // keeps running in the background.
  final a = await fetchBtcPrice(latencyMs: 300).withDeadline(
    const Duration(milliseconds: 50),
    fallback: 60000.0,
    cacheKey: key,
  );
  print('  Call A: \$${a.value}  [${a.source.name}]');

  // Wait for the background Future to land.
  await Future<void>.delayed(const Duration(milliseconds: 400));

  // Call B: the cache is now populated thanks to the late arrival.
  final b = await fetchBtcPrice(latencyMs: 5000).withDeadline(
    const Duration(milliseconds: 20),
    cacheKey: key,
    fallback: 60000.0,
  );
  print('  Call B: \$${b.value}  [${b.source.name}]');
  // Expected → Call B source: cached (67432.50) — not the fallback!
}

// ─────────────────────────────────────────────────────────────────────────────
// main
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print(' deadline_future — usage examples');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  await example1_simpleFallback();
  await example2_smartCache();
  await example3_uiIndicator();
  await example4_patternMatching();
  await example5_durationSugar();
  await example6_batchFeed();
  await example7_chat();
  await example8_globalConfig();
  await example9_exceptionHandling();
  await example10_lateArrivalHealsCache();

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print(' All examples completed.');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}
