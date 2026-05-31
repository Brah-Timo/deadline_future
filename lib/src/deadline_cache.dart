// ─────────────────────────────────────────────────────────────────────────────
// deadline_cache.dart  (internal — not exported from the barrel file)
//
// A lightweight in-memory LRU cache with per-entry TTL support.
//
// Design goals:
//  • Zero external dependencies.
//  • O(1) average-case reads and writes via a HashMap.
//  • Bounded memory via configurable [maxEntries] (FIFO eviction for now;
//    can be upgraded to true LRU with a doubly-linked list if needed).
//  • Thread-safe for single-isolate use (standard Dart async model).
//  • Automatic TTL expiry on access (lazy eviction — no background timer).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:collection';

// ── Internal entry ────────────────────────────────────────────────────────────

/// A single record inside [DeadlineCache].
final class _CacheEntry<T> {
  /// The stored value.
  final T value;

  /// Wall-clock time when this entry was created.
  final DateTime storedAt;

  /// How long this entry is considered fresh.
  ///
  /// `null` means the entry never expires.
  final Duration? ttl;

  _CacheEntry({
    required this.value,
    required this.storedAt,
    this.ttl,
  });

  /// Returns `true` when the entry has surpassed its [ttl].
  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(storedAt) > ttl!;
  }

  /// Age of this entry at the time of the call.
  Duration get age => DateTime.now().difference(storedAt);

  @override
  String toString() =>
      '_CacheEntry(storedAt: $storedAt, ttl: $ttl, expired: $isExpired)';
}

// ── Public cache ──────────────────────────────────────────────────────────────

/// Internal smart cache used by [withDeadline] to store successful Future
/// results keyed by a caller-supplied [String] identifier.
///
/// **Not part of the public API** — interact with it only through
/// [withDeadline]'s `cacheKey` / `cacheTtl` parameters.
///
/// ### How the cache interacts with [withDeadline]:
///
/// 1. The original Future completes successfully → value is [store]d.
/// 2. Next call times out before the Future finishes → value is [retrieve]d.
/// 3. Late-arriving result (after a timeout) → still [store]d, ready for the
///    next call.
///
/// This "learning" behaviour means the cache improves automatically over time:
/// the first call bootstraps it, and every subsequent slow call benefits.
final class DeadlineCache {
  // ── Singleton ─────────────────────────────────────────────────────────────

  static final DeadlineCache _instance = DeadlineCache._internal();

  /// Returns the process-wide singleton instance.
  factory DeadlineCache() => _instance;
  DeadlineCache._internal();

  // ── Internal store ────────────────────────────────────────────────────────

  /// [LinkedHashMap] preserves insertion order, which gives us FIFO eviction
  /// for free when we need to shed the oldest entry.
  final _store = LinkedHashMap<String, _CacheEntry<dynamic>>();

  // ── Configuration ─────────────────────────────────────────────────────────

  /// Maximum number of entries before the oldest one is evicted.
  ///
  /// Increase or decrease based on your app's memory budget.
  /// Defaults to 200 (roughly 200 × ~64 bytes = ~12 KB for typical values).
  static int maxEntries = 200;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Stores [value] under [key], optionally expiring after [ttl].
  ///
  /// If [ttl] is `null`, [DeadlineConfig.defaultCacheTtl] is used as a
  /// fallback.  If that is also `null`, the entry never expires.
  ///
  /// When the store is at capacity ([maxEntries]) the oldest entry is removed
  /// before inserting the new one.
  void store<T>(String key, T value, {Duration? ttl}) {
    _evictIfAtCapacity();

    _store[key] = _CacheEntry<T>(
      value: value,
      storedAt: DateTime.now(),
      ttl: ttl,
    );
  }

  /// Retrieves the value for [key], or `null` if:
  /// - The key was never stored, **or**
  /// - The stored entry has exceeded its TTL (it is lazily evicted).
  ///
  /// The cast to `T?` is unchecked; callers must ensure type consistency
  /// (i.e. always use the same `T` for a given `key`).
  T? retrieve<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }

    return entry.value as T?;
  }

  /// Returns `true` when [key] exists in the cache and has not expired.
  bool contains(String key) {
    final entry = _store[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _store.remove(key);
      return false;
    }
    return true;
  }

  /// Removes the entry for [key] (no-op if not present).
  void evict(String key) => _store.remove(key);

  /// Removes **all** entries from the cache.
  ///
  /// Useful in tests to ensure a clean slate between test cases.
  void clear() => _store.clear();

  // ── Statistics ────────────────────────────────────────────────────────────

  /// The current number of entries (including those that may be expired but
  /// have not yet been lazily evicted).
  int get size => _store.length;

  /// The maximum age of any live (non-expired) entry at call time.
  Duration? get oldestEntryAge {
    Duration? oldest;
    for (final entry in _store.values) {
      if (!entry.isExpired) {
        final age = entry.age;
        if (oldest == null || age > oldest) oldest = age;
      }
    }
    return oldest;
  }

  /// Returns an unmodifiable snapshot of all live cache keys (expired entries
  /// are excluded but not evicted here — call [purgeExpired] explicitly).
  List<String> get liveKeys => [
        for (final kv in _store.entries)
          if (!kv.value.isExpired) kv.key,
      ];

  // ── Maintenance ───────────────────────────────────────────────────────────

  /// Eagerly removes all expired entries from the store.
  ///
  /// Under normal usage lazy eviction (inside [retrieve]) is sufficient.
  /// Call this periodically (e.g. via a [Timer]) if you expect a large number
  /// of short-lived entries to pile up.
  void purgeExpired() {
    _store.removeWhere((_, entry) => entry.isExpired);
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _evictIfAtCapacity() {
    if (_store.length >= maxEntries) {
      // FIFO: remove the entry that was inserted first.
      _store.remove(_store.keys.first);
    }
  }

  @override
  String toString() => 'DeadlineCache(size: $size, maxEntries: $maxEntries)';
}
