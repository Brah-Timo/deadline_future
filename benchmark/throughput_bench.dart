// ignore_for_file: avoid_print

/// deadline_future — Performance benchmarks
///
/// Compares withDeadline() against native Future.timeout() in three scenarios:
///   1. Fast Future (completes well before deadline) — best-case path
///   2. Timeout with fallback  — timer branch path
///   3. Cache hit after a warm-up call — cache branch path
///
/// Run with:
///   dart run benchmark/throughput_bench.dart
library;

import 'dart:async';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:deadline_future/deadline_future.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark 1 — withDeadline, Future completes within deadline
// ─────────────────────────────────────────────────────────────────────────────

class WithDeadlineCompletedBench extends AsyncBenchmarkBase {
  WithDeadlineCompletedBench()
      : super('withDeadline — completed (future wins)');

  @override
  Future<void> run() async {
    await Future<int>.value(42).withDeadline(
      const Duration(seconds: 1),
      fallback: 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark 2 — native Future.timeout, Future completes within deadline
// ─────────────────────────────────────────────────────────────────────────────

class NativeTimeoutCompletedBench extends AsyncBenchmarkBase {
  NativeTimeoutCompletedBench()
      : super('Future.timeout  — completed (native baseline)');

  @override
  Future<void> run() async {
    await Future<int>.value(42).timeout(
      const Duration(seconds: 1),
      onTimeout: () => 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark 3 — withDeadline, timer fires (fallback path)
// ─────────────────────────────────────────────────────────────────────────────

class WithDeadlineTimeoutBench extends AsyncBenchmarkBase {
  WithDeadlineTimeoutBench() : super('withDeadline — timeout (fallback path)');

  @override
  Future<void> run() async {
    await Future<int>.delayed(
      const Duration(milliseconds: 100),
      () => 1,
    ).withDeadline(
      const Duration(milliseconds: 1),
      fallback: 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark 4 — native Future.timeout, timer fires
// ─────────────────────────────────────────────────────────────────────────────

class NativeTimeoutTimeoutBench extends AsyncBenchmarkBase {
  NativeTimeoutTimeoutBench()
      : super('Future.timeout  — timeout (native baseline)');

  @override
  Future<void> run() async {
    await Future<int>.delayed(
      const Duration(milliseconds: 100),
      () => 1,
    ).timeout(
      const Duration(milliseconds: 1),
      onTimeout: () => 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark 5 — withDeadline, cache hit (warm cache)
// ─────────────────────────────────────────────────────────────────────────────

class WithDeadlineCacheHitBench extends AsyncBenchmarkBase {
  WithDeadlineCacheHitBench() : super('withDeadline — cache hit (warm cache)');

  @override
  Future<void> setUp() async {
    // Prime the cache once before the benchmark loop.
    DeadlineConfig.reset();
    await Future<int>.value(42).withDeadline(
      const Duration(seconds: 1),
      cacheKey: 'bench_cache_key',
    );
  }

  @override
  Future<void> run() async {
    // Timer fires immediately; cache provides value.
    await Future<int>.delayed(
      const Duration(milliseconds: 100),
      () => 1,
    ).withDeadline(
      const Duration(milliseconds: 1),
      cacheKey: 'bench_cache_key',
    );
  }

  // ignore: override_on_non_overriding_member
  Future<void> teardown() async => DeadlineConfig.reset();
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark 6 — overhead of DeadlineDuration shorthand (compile-time only)
// ─────────────────────────────────────────────────────────────────────────────

class DurationShorthandBench extends AsyncBenchmarkBase {
  DurationShorthandBench() : super('withDeadline — using int.seconds sugar');

  @override
  Future<void> run() async {
    await Future<String>.value('hello').withDeadline(1.seconds);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// main
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  print('┌─────────────────────────────────────────────────────────────┐');
  print('│         deadline_future — Benchmark Suite                   │');
  print('│  Lower µs/call = better.  All times in microseconds.        │');
  print('└─────────────────────────────────────────────────────────────┘\n');

  // Group 1 — Completed path
  print('── Fast-path (Future completes before deadline) ─────────────');
  await WithDeadlineCompletedBench().report();
  await NativeTimeoutCompletedBench().report();

  print('\n── Timeout path (timer fires, fallback returned) ────────────');
  await WithDeadlineTimeoutBench().report();
  await NativeTimeoutTimeoutBench().report();

  print('\n── Cache-hit path (warm cache, no live Future needed) ───────');
  await WithDeadlineCacheHitBench().report();

  print('\n── Duration shorthand sugar ─────────────────────────────────');
  await DurationShorthandBench().report();

  print('\n✔  Benchmark complete.');
}
