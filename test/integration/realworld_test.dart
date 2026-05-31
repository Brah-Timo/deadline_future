// ─────────────────────────────────────────────────────────────────────────────
// integration/realworld_test.dart
//
// End-to-end scenarios that simulate real application patterns:
//   • Crypto price feed with variable latency
//   • Chat message delivery with graceful degradation
//   • Live dashboard with multi-feed batch queries
//   • Retry pattern built on top of withDeadline
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:deadline_future/deadline_future.dart';
import 'package:test/test.dart';

// ── Fake API layer ─────────────────────────────────────────────────────────

class FakePriceApi {
  int callCount = 0;
  int _latencyMs;
  double _price;

  FakePriceApi({required int latencyMs, required double price})
      : _latencyMs = latencyMs,
        _price = price;

  void setLatency(int ms) => _latencyMs = ms;
  void setPrice(double p) => _price = p;

  Future<double> fetchPrice(String symbol) async {
    callCount++;
    await Future<void>.delayed(Duration(milliseconds: _latencyMs));
    return _price;
  }
}

class FakeChatApi {
  Future<String> fetchMessages(String roomId) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return 'Hello from room $roomId';
  }
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  setUp(() => DeadlineConfig.reset());

  // ── Crypto price feed ────────────────────────────────────────────────────
  group('Real-world: crypto price feed', () {
    test('fast network — returns live price with completed source', () async {
      final api = FakePriceApi(latencyMs: 50, price: 67000.0);

      final result = await api.fetchPrice('BTC').withDeadline(
        const Duration(milliseconds: 500),
        cacheKey: 'btc',
        fallback: 60000.0,
      );

      expect(result.value, equals(67000.0));
      expect(result.source, equals(DeadlineResultSource.completed));
      expect(result.isLive, isTrue);
      expect(api.callCount, equals(1));
    });

    test('slow network — returns cached price from previous call', () async {
      final api = FakePriceApi(latencyMs: 30, price: 67000.0);

      // First call: fast → primes cache.
      await api.fetchPrice('BTC').withDeadline(
        const Duration(milliseconds: 500),
        cacheKey: 'btc_cache',
      );

      // Simulate network degradation.
      api.setLatency(2000);

      // Second call: slow → hits cache.
      final degraded = await api.fetchPrice('BTC').withDeadline(
        const Duration(milliseconds: 100),
        cacheKey: 'btc_cache',
        fallback: 50000.0,
        onTimeout: () {},
      );

      expect(degraded.value, equals(67000.0));
      expect(degraded.source, equals(DeadlineResultSource.cached));
      expect(degraded.isDegraded, isTrue);
    });

    test('no cache, no fallback, slow network → throws exception', () async {
      final api = FakePriceApi(latencyMs: 2000, price: 0.0);

      await expectLater(
        api.fetchPrice('ETH').withDeadline(
          const Duration(milliseconds: 50),
        ),
        throwsA(isA<DeadlineExceededException>()),
      );
    });

    test('price updates in cache after late arrival', () async {
      final api = FakePriceApi(latencyMs: 200, price: 70000.0);

      // Prime with slow future; cache gets 70_000 after 200ms.
      await Future.any([
        api.fetchPrice('BTC').withDeadline(
          const Duration(milliseconds: 50),
          fallback: 65000.0,
          cacheKey: 'btc_late',
        ),
      ]);

      // Wait for the background Future to land in cache.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Next timeout call should serve 70_000 from cache.
      api.setLatency(2000);
      final next = await api.fetchPrice('BTC').withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'btc_late',
        fallback: 0.0,
      );

      expect(next.source, equals(DeadlineResultSource.cached));
      expect(next.value, equals(70000.0));
    });
  });

  // ── Chat messages ────────────────────────────────────────────────────────
  group('Real-world: chat messages', () {
    test('messages delivered within deadline', () async {
      final api = FakeChatApi();

      final result = await api.fetchMessages('room_1').withDeadline(
        const Duration(milliseconds: 500),
        cacheKey: 'chat_room_1',
        fallback: '(no messages)',
      );

      expect(result.value, contains('room_1'));
      expect(result.isLive, isTrue);
    });

    test('stale messages served from cache when server is slow', () async {
      final api = FakeChatApi();

      // Prime cache.
      await api.fetchMessages('room_2').withDeadline(
        const Duration(milliseconds: 500),
        cacheKey: 'chat_room_2',
      );

      // Simulate slow server — use a delayed future directly.
      final result = await Future<String>.delayed(
        const Duration(seconds: 5),
        () => 'fresh messages',
      ).withDeadline(
        const Duration(milliseconds: 20),
        cacheKey: 'chat_room_2',
        fallback: '(offline)',
      );

      expect(result.isDegraded, isTrue);
      expect(result.source, equals(DeadlineResultSource.cached));
    });
  });

  // ── Live dashboard batch feed ────────────────────────────────────────────
  group('Real-world: live dashboard — batch withDeadlineAll', () {
    test('fetches multiple feeds concurrently', () async {
      final symbols = ['BTC', 'ETH', 'SOL'];
      final prices = <String, double>{
        'BTC': 67000.0,
        'ETH': 3500.0,
        'SOL': 180.0,
      };

      final futures = symbols
          .map((s) => Future<double>.delayed(
                const Duration(milliseconds: 40),
                () => prices[s]!,
              ))
          .toList();

      final results = await futures.withDeadlineAll(
        const Duration(milliseconds: 500),
        cacheKeys: symbols,
        fallback: 0.0,
      );

      expect(results.length, equals(3));
      expect(results[0].value, equals(67000.0));
      expect(results[1].value, equals(3500.0));
      expect(results[2].value, equals(180.0));
      expect(
        results.every((r) => r.source == DeadlineResultSource.completed),
        isTrue,
      );
    });

    test('partial timeout — some feeds from cache, some live', () async {
      // Prime BTC cache.
      await Future<double>.value(67000.0).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'dash_BTC',
      );

      // BTC: slow → from cache.  ETH: fast → live.
      final results = await [
        Future<double>.delayed(
          const Duration(milliseconds: 500),
          () => 68000.0,
        ), // BTC slow
        Future<double>.delayed(
          const Duration(milliseconds: 30),
          () => 3600.0,
        ), // ETH fast
      ].withDeadlineAll(
        const Duration(milliseconds: 100),
        cacheKeys: ['dash_BTC', 'dash_ETH'],
        fallback: 0.0,
      );

      expect(results[0].source, equals(DeadlineResultSource.cached));
      expect(results[1].source, equals(DeadlineResultSource.completed));
    });
  });

  // ── Retry wrapper built on withDeadline ──────────────────────────────────
  group('Real-world: retry pattern', () {
    test('retry up to N times, succeeds on second attempt', () async {
      var attempt = 0;

      Future<String> unstable() async {
        attempt++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        if (attempt < 2) throw Exception('network error');
        return 'success';
      }

      Future<DeadlineResult<String>> retryWithDeadline(
        int maxAttempts,
        Duration perAttemptDeadline,
      ) async {
        DeadlineResult<String>? last;
        for (var i = 0; i < maxAttempts; i++) {
          try {
            final r = await unstable().withDeadline(
              perAttemptDeadline,
              fallback: 'fallback',
            );
            if (r.isLive) return r;
            last = r;
          } catch (_) {
            last ??= DeadlineResult<String>(
              value: 'fallback',
              isTimedOut: false,
              source: DeadlineResultSource.fallback,
              resolvedAt: DateTime.now(),
            );
          }
        }
        return last!;
      }

      final result = await retryWithDeadline(3, const Duration(seconds: 1));
      expect(result.value, equals('success'));
      expect(attempt, equals(2));
    });
  });

  // ── DeadlineDuration sugar in real call ──────────────────────────────────
  group('Real-world: Duration shorthand ergonomics', () {
    test('3.seconds works as deadline in withDeadline', () async {
      final result = await Future<String>.value('ok').withDeadline(3.seconds);
      expect(result.isLive, isTrue);
    });

    test('50.milliseconds triggers timeout on slow Future', () async {
      final result = await Future<String>.delayed(
        const Duration(seconds: 5),
        () => 'slow',
      ).withDeadline(
        50.milliseconds,
        fallback: 'fast_fallback',
      );

      expect(result.isTimedOut, isTrue);
      expect(result.value, equals('fast_fallback'));
    });
  });
}
