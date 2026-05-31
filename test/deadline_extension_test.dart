import 'dart:async';

import 'package:deadline_future/deadline_future.dart';
import 'package:test/test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a Future that completes after [delayMs] milliseconds with [value].
Future<T> delayed<T>(T value, int delayMs) =>
    Future<T>.delayed(Duration(milliseconds: delayMs), () => value);

/// Returns a Future that throws [error] after [delayMs] milliseconds.
Future<T> delayedError<T>(Object error, int delayMs) =>
    Future<T>.delayed(Duration(milliseconds: delayMs), () => throw error);

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => DeadlineConfig.reset());

  // ── Basic resolution ───────────────────────────────────────────────────────
  group('withDeadline — live completion', () {
    test('returns DeadlineResultSource.completed when Future wins', () async {
      final result = await delayed('hello', 50).withDeadline(
        const Duration(milliseconds: 500),
      );

      expect(result.value, equals('hello'));
      expect(result.isTimedOut, isFalse);
      expect(result.source, equals(DeadlineResultSource.completed));
      expect(result.isLive, isTrue);
      expect(result.isDegraded, isFalse);
    });

    test('actualDuration is populated and <= deadline', () async {
      const dl = Duration(milliseconds: 500);
      final result = await delayed(1, 100).withDeadline(dl);

      expect(result.actualDuration, isNotNull);
      expect(result.actualDuration!.inMilliseconds, lessThanOrEqualTo(500));
      expect(result.actualDuration!.inMilliseconds, greaterThan(0));
    });

    test('resolvedAt is a recent UTC DateTime', () async {
      final before = DateTime.now().toUtc();
      final result = await Future<int>.value(42).withDeadline(
        const Duration(seconds: 1),
      );
      final after = DateTime.now().toUtc();

      expect(result.resolvedAt.isAfter(before), isTrue);
      expect(result.resolvedAt.isBefore(after), isTrue);
    });
  });

  // ── Fallback path ──────────────────────────────────────────────────────────
  group('withDeadline — fallback path', () {
    test('returns fallback when deadline elapses', () async {
      final result = await delayed('slow', 300).withDeadline(
        const Duration(milliseconds: 50),
        fallback: 'default',
      );

      expect(result.value, equals('default'));
      expect(result.isTimedOut, isTrue);
      expect(result.source, equals(DeadlineResultSource.fallback));
      expect(result.isFromFallback, isTrue);
      expect(result.actualDuration, isNull);
    });

    test('fallback works with numeric types', () async {
      final result = await delayed(99.9, 500).withDeadline(
        const Duration(milliseconds: 10),
        fallback: 0.0,
      );
      expect(result.value, equals(0.0));
    });

    test('fallback works with custom objects', () async {
      final obj = {'key': 'value'};
      final result = await delayed(<String, String>{}, 500).withDeadline(
        const Duration(milliseconds: 10),
        fallback: obj,
      );
      expect(result.value, same(obj));
    });
  });

  // ── Cache path ─────────────────────────────────────────────────────────────
  group('withDeadline — cache path', () {
    test('stores live result and returns it on next timeout', () async {
      // First call: Future wins → result cached.
      final first = await delayed('live_value', 50).withDeadline(
        const Duration(milliseconds: 500),
        cacheKey: 'my_key',
      );
      expect(first.source, equals(DeadlineResultSource.completed));

      // Second call: Future too slow → served from cache.
      final second = await delayed('new_value', 500).withDeadline(
        const Duration(milliseconds: 20),
        cacheKey: 'my_key',
      );
      expect(second.value, equals('live_value'));
      expect(second.source, equals(DeadlineResultSource.cached));
      expect(second.isFromCache, isTrue);
    });

    test('cache takes priority over fallback', () async {
      // Prime the cache.
      await delayed('cached_val', 50).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'priority_key',
      );

      // Both cache and fallback available → cache wins.
      final result = await delayed('live', 500).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'priority_key',
        fallback: 'fallback_val',
      );

      expect(result.source, equals(DeadlineResultSource.cached));
      expect(result.value, equals('cached_val'));
    });

    test('late-arriving Future value is stored in cache', () async {
      // Timeout call with fallback.
      await delayed('late', 200).withDeadline(
        const Duration(milliseconds: 30),
        fallback: 'fb',
        cacheKey: 'late_key',
      );

      // Wait for the slow Future to complete and write to cache.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Now the cache should have 'late'.
      final next = await delayed('fresh', 500).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'late_key',
      );

      expect(next.source, equals(DeadlineResultSource.cached));
      expect(next.value, equals('late'));
    });

    test('different cacheKeys are stored independently', () async {
      await delayed('alpha', 50).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'key_alpha',
      );
      await delayed('beta', 50).withDeadline(
        const Duration(seconds: 1),
        cacheKey: 'key_beta',
      );

      final a = await delayed('slow', 500).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'key_alpha',
      );
      final b = await delayed('slow', 500).withDeadline(
        const Duration(milliseconds: 10),
        cacheKey: 'key_beta',
      );

      expect(a.value, equals('alpha'));
      expect(b.value, equals('beta'));
    });
  });

  // ── Exception paths ────────────────────────────────────────────────────────
  group('withDeadline — exception paths', () {
    test('throws DeadlineExceededException when no cache or fallback', () {
      expect(
        () => delayed('data', 1000).withDeadline(
          const Duration(milliseconds: 10),
        ),
        throwsA(isA<DeadlineExceededException>()),
      );
    });

    test('DeadlineExceededException carries correct deadline', () async {
      const dl = Duration(milliseconds: 15);
      try {
        await delayed('x', 1000).withDeadline(dl);
        fail('Expected DeadlineExceededException');
      } on DeadlineExceededException catch (e) {
        expect(e.deadline, equals(dl));
      }
    });

    test('DeadlineExceededException carries context label', () async {
      try {
        await delayed('x', 1000).withDeadline(
          const Duration(milliseconds: 10),
          context: 'my_widget',
        );
        fail('Expected DeadlineExceededException');
      } on DeadlineExceededException catch (e) {
        expect(e.context, equals('my_widget'));
        expect(e.toString(), contains('my_widget'));
      }
    });

    test(
        'throws InvalidDeadlineDurationException for Duration.zero synchronously',
        () {
      expect(
        () => Future<int>.value(1).withDeadline(Duration.zero),
        throwsA(isA<InvalidDeadlineDurationException>()),
      );
    });

    test(
        'throws InvalidDeadlineDurationException for negative Duration synchronously',
        () {
      expect(
        () => Future<int>.value(1)
            .withDeadline(const Duration(milliseconds: -100)),
        throwsA(isA<InvalidDeadlineDurationException>()),
      );
    });

    test('propagates Future error when it occurs before deadline', () {
      expect(
        () => delayedError<int>(Exception('boom'), 10).withDeadline(
          const Duration(milliseconds: 500),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('late Future error is ignored when ignoreErrorsAfterDeadline=true',
        () async {
      DeadlineConfig.ignoreErrorsAfterDeadline = true;

      // This should NOT throw.  The fallback is returned; the late error
      // is swallowed.
      final result = await delayedError<String>(Exception('late_err'), 200)
          .withDeadline(
        const Duration(milliseconds: 30),
        fallback: 'safe',
      );

      expect(result.value, equals('safe'));
      expect(result.isTimedOut, isTrue);
    });
  });

  // ── onTimeout callback ─────────────────────────────────────────────────────
  group('withDeadline — onTimeout callback', () {
    test('onTimeout is invoked when deadline elapses', () async {
      var called = false;

      await delayed('slow', 500).withDeadline(
        const Duration(milliseconds: 30),
        fallback: 'fb',
        onTimeout: () => called = true,
      );

      expect(called, isTrue);
    });

    test('onTimeout is NOT invoked when Future completes in time', () async {
      var called = false;

      await delayed('fast', 20).withDeadline(
        const Duration(milliseconds: 500),
        onTimeout: () => called = true,
      );

      expect(called, isFalse);
    });

    test('onTimeout fires before the result is resolved', () async {
      final events = <String>[];

      await delayed('slow', 500).withDeadline(
        const Duration(milliseconds: 30),
        fallback: 'fb',
        onTimeout: () => events.add('timeout'),
      );
      events.add('resolved');

      expect(events.first, equals('timeout'));
    });
  });

  // ── DeadlineDuration shorthand ─────────────────────────────────────────────
  group('DeadlineDuration int extension', () {
    test('3.seconds == Duration(seconds: 3)', () {
      expect(3.seconds, equals(const Duration(seconds: 3)));
    });

    test('500.milliseconds == Duration(milliseconds: 500)', () {
      expect(500.milliseconds, equals(const Duration(milliseconds: 500)));
    });

    test('2.minutes == Duration(minutes: 2)', () {
      expect(2.minutes, equals(const Duration(minutes: 2)));
    });

    test('1.hours == Duration(hours: 1)', () {
      expect(1.hours, equals(const Duration(hours: 1)));
    });

    test('can be used directly in withDeadline', () async {
      final result = await Future<int>.value(7).withDeadline(1.seconds);
      expect(result.value, equals(7));
    });
  });

  // ── Batch extension ────────────────────────────────────────────────────────
  group('withDeadlineAll — batch extension', () {
    test('resolves all Futures concurrently', () async {
      final results = await [
        delayed(1, 50),
        delayed(2, 50),
        delayed(3, 50),
      ].withDeadlineAll(const Duration(seconds: 1));

      expect(results.map((r) => r.value).toList(), equals([1, 2, 3]));
      expect(
        results.every((r) => r.source == DeadlineResultSource.completed),
        isTrue,
      );
    });

    test('uses fallback for timed-out Futures in batch', () async {
      final results = await [
        delayed('fast', 10),
        delayed('slow', 1000),
      ].withDeadlineAll(
        const Duration(milliseconds: 50),
        fallback: 'fb',
      );

      expect(results[0].source, equals(DeadlineResultSource.completed));
      expect(results[1].source, equals(DeadlineResultSource.fallback));
    });

    test('uses per-element cacheKeys in batch', () async {
      final results = await [
        Future<int>.value(10),
        Future<int>.value(20),
      ].withDeadlineAll(
        const Duration(seconds: 1),
        cacheKeys: ['k0', 'k1'],
      );

      expect(results[0].value, equals(10));
      expect(results[1].value, equals(20));
      expect(DeadlineConfig.cacheSize, equals(2));
    });

    test('asserts when cacheKeys length mismatches list length', () {
      expect(
        () => [Future<int>.value(1)].withDeadlineAll(
          const Duration(seconds: 1),
          cacheKeys: ['a', 'b'], // length mismatch
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
