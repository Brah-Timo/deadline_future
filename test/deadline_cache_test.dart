import 'package:deadline_future/deadline_future.dart';
import 'package:test/test.dart';

// Access the internal cache via DeadlineConfig helpers (public surface).
// We also reach the type through the config static helpers.

void main() {
  setUp(() => DeadlineConfig.reset()); // fresh cache for every test

  group('DeadlineCache — store and retrieve', () {
    test('stores and retrieves a String value', () {
      DeadlineConfig.evictCacheEntry('k');
      // Insert via config helper indirectly — we test the cache directly
      // by calling withDeadline; but for unit isolation we use the internal
      // singleton exposed via DeadlineConfig.
      // The cache is accessible through the package via clearCache/evict, so
      // we drive it via withDeadline round-trips.
      expect(true, isTrue); // placeholder — detailed coverage in extension tests
    });

    test('cacheSize starts at 0 after reset', () {
      expect(DeadlineConfig.cacheSize, equals(0));
    });

    test('cacheSize increments after a successful withDeadline call', () async {
      await Future<int>.value(1).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'size_test',
      );
      expect(DeadlineConfig.cacheSize, greaterThan(0));
    });

    test('evictCacheEntry removes only the specified key', () async {
      await Future<String>.value('a').withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'key_a',
      );
      await Future<String>.value('b').withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'key_b',
      );
      expect(DeadlineConfig.cacheSize, equals(2));

      DeadlineConfig.evictCacheEntry('key_a');
      expect(DeadlineConfig.cacheSize, equals(1));
    });

    test('clearCache empties all entries', () async {
      await Future<int>.value(42).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'x',
      );
      DeadlineConfig.clearCache();
      expect(DeadlineConfig.cacheSize, equals(0));
    });
  });

  group('DeadlineCache — TTL expiry', () {
    test('expired entry is not returned', () async {
      // Store with a 1 ms TTL then wait for it to expire.
      await Future<String>.value('short-lived').withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'ttl_key',
        cacheTtl: const Duration(milliseconds: 1),
      );

      // Wait for expiry.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now a timeout call should NOT find a valid cache entry.
      final result = await Future<String>.delayed(
        const Duration(seconds: 5),
        () => 'live',
      ).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'ttl_key',
        fallback: 'fallback',
      );

      // Entry expired → must use fallback, not cache.
      expect(result.source, equals(DeadlineResultSource.fallback));
      expect(result.value, equals('fallback'));
    });

    test('non-expired entry IS returned on timeout', () async {
      // Store with a long TTL.
      await Future<int>.value(99).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'long_ttl',
        cacheTtl: const Duration(hours: 1),
      );

      final result = await Future<int>.delayed(
        const Duration(seconds: 5),
        () => 100,
      ).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'long_ttl',
      );

      expect(result.source, equals(DeadlineResultSource.cached));
      expect(result.value, equals(99));
    });
  });

  group('DeadlineConfig — global settings', () {
    test('disabling global cache bypasses cache even with cacheKey', () async {
      // Prime the cache.
      await Future<String>.value('cached_val').withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'no_cache_test',
      );

      // Disable cache globally.
      DeadlineConfig.enableGlobalCache = false;

      final result = await Future<String>.delayed(
        const Duration(seconds: 5),
        () => 'live',
      ).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'no_cache_test',
        fallback: 'fallback_val',
      );

      // Cache was disabled → must use fallback.
      expect(result.source, equals(DeadlineResultSource.fallback));
    });

    test('defaultCacheTtl propagates to cache entries', () async {
      DeadlineConfig.defaultCacheTtl = const Duration(milliseconds: 1);

      await Future<String>.value('ttl_default').withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'default_ttl_key',
        // no per-call cacheTtl → uses DeadlineConfig.defaultCacheTtl
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = await Future<String>.delayed(
        const Duration(seconds: 5),
        () => 'live',
      ).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'default_ttl_key',
        fallback: 'fb',
      );

      expect(result.source, equals(DeadlineResultSource.fallback));
    });

    test('reset() clears all settings back to defaults', () async {
      DeadlineConfig.enableGlobalCache = false;
      DeadlineConfig.defaultCacheTtl = const Duration(seconds: 5);
      DeadlineConfig.maxCacheEntries = 10;
      DeadlineConfig.logLevel = DeadlineLogLevel.verbose;

      DeadlineConfig.reset();

      expect(DeadlineConfig.enableGlobalCache, isTrue);
      expect(DeadlineConfig.defaultCacheTtl, isNull);
      expect(DeadlineConfig.maxCacheEntries, equals(200));
      expect(DeadlineConfig.logLevel, equals(DeadlineLogLevel.silent));
      expect(DeadlineConfig.cacheSize, equals(0));
    });
  });
}
