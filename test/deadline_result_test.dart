// ignore_for_file: prefer_const_constructors

import 'package:deadline_future/deadline_future.dart';
import 'package:test/test.dart';

void main() {
  group('DeadlineResult — construction and basic fields', () {
    late DateTime ts;

    setUp(() => ts = DateTime.utc(2025, 1, 1, 12));

    test('stores value, source, and resolvedAt correctly', () {
      final r = DeadlineResult<int>(
        value: 42,
        isTimedOut: false,
        source: DeadlineResultSource.completed,
        actualDuration: const Duration(milliseconds: 120),
        resolvedAt: ts,
      );

      expect(r.value, equals(42));
      expect(r.isTimedOut, isFalse);
      expect(r.source, equals(DeadlineResultSource.completed));
      expect(r.actualDuration, equals(const Duration(milliseconds: 120)));
      expect(r.resolvedAt, equals(ts));
    });

    test('fallback entry has correct flags', () {
      final r = DeadlineResult<String>(
        value: 'default',
        isTimedOut: true,
        source: DeadlineResultSource.fallback,
        resolvedAt: ts,
      );

      expect(r.isTimedOut, isTrue);
      expect(r.isDegraded, isTrue);
      expect(r.isLive, isFalse);
      expect(r.isFromFallback, isTrue);
      expect(r.isFromCache, isFalse);
      expect(r.actualDuration, isNull);
    });

    test('cached entry has correct flags', () {
      final r = DeadlineResult<double>(
        value: 1.5,
        isTimedOut: true,
        source: DeadlineResultSource.cached,
        resolvedAt: ts,
      );

      expect(r.isDegraded, isTrue);
      expect(r.isFromCache, isTrue);
      expect(r.isFromFallback, isFalse);
    });

    test('completed entry has correct flags', () {
      final r = DeadlineResult<bool>(
        value: true,
        isTimedOut: false,
        source: DeadlineResultSource.completed,
        resolvedAt: ts,
      );

      expect(r.isLive, isTrue);
      expect(r.isDegraded, isFalse);
    });
  });

  group('DeadlineResult — equality and hashCode', () {
    final ts = DateTime.utc(2025, 6, 15);

    DeadlineResult<int> make() => DeadlineResult<int>(
          value: 7,
          isTimedOut: false,
          source: DeadlineResultSource.completed,
          actualDuration: const Duration(milliseconds: 50),
          resolvedAt: ts,
        );

    test('two identical instances are equal', () {
      expect(make(), equals(make()));
    });

    test('hashCode is stable for equal instances', () {
      expect(make().hashCode, equals(make().hashCode));
    });

    test('instances with different values are not equal', () {
      final a = make();
      final b = a.copyWith(value: 99);
      expect(a, isNot(equals(b)));
    });

    test('instances with different sources are not equal', () {
      final a = make();
      final b = a.copyWith(source: DeadlineResultSource.cached);
      expect(a, isNot(equals(b)));
    });
  });

  group('DeadlineResult — copyWith', () {
    final ts = DateTime.utc(2024, 3, 10);
    final base = DeadlineResult<String>(
      value: 'original',
      isTimedOut: false,
      source: DeadlineResultSource.completed,
      resolvedAt: ts,
    );

    test('copyWith overrides value', () {
      final copy = base.copyWith(value: 'updated');
      expect(copy.value, equals('updated'));
      expect(copy.source, equals(base.source)); // unchanged
    });

    test('copyWith overrides source', () {
      final copy = base.copyWith(source: DeadlineResultSource.fallback);
      expect(copy.source, equals(DeadlineResultSource.fallback));
      expect(copy.value, equals(base.value)); // unchanged
    });

    test('copyWith overrides isTimedOut', () {
      final copy = base.copyWith(isTimedOut: true);
      expect(copy.isTimedOut, isTrue);
    });

    test('copyWith with no arguments returns equal instance', () {
      expect(base.copyWith(), equals(base));
    });
  });

  group('DeadlineResult — toString', () {
    test('contains all key fields', () {
      final r = DeadlineResult<int>(
        value: 100,
        isTimedOut: false,
        source: DeadlineResultSource.completed,
        actualDuration: const Duration(milliseconds: 300),
        resolvedAt: DateTime.utc(2025, 1, 1),
      );
      final s = r.toString();
      expect(s, contains('100'));
      expect(s, contains('completed'));
      expect(s, contains('300'));
    });
  });
}
