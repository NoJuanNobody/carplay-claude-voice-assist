import Foundation

// MARK: - CachedResponse

/// A cached response with metadata for expiration and provenance.
public struct CachedResponse: Codable, Sendable {
    /// The response text content.
    public let text: String

    /// When this response was cached.
    public let cachedAt: Date

    /// When this cached response expires.
    public let expiresAt: Date

    /// The source that produced this response (e.g., "claude_api", "offline_fallback").
    public let source: String

    /// Whether this cached response has expired.
    public var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - CacheEntry

/// Internal wrapper that associates a query with its cached response.
private struct CacheEntry: Codable {
    let query: String
    let response: CachedResponse
    var lastAccessedAt: Date
}

// MARK: - OfflineCacheManager

/// Manages persistent caching of responses for offline use.
///
/// Uses FileManager to store cached responses in the Documents directory.
/// Implements LRU eviction when the cache exceeds the maximum size (50MB),
/// and automatically expires entries older than the TTL (24 hours).
public final class OfflineCacheManager {

    // MARK: - Constants

    /// Time-to-live for cached responses: 24 hours.
    public static let defaultTTL: TimeInterval = 24 * 60 * 60

    /// Maximum cache size in bytes: 50MB.
    public static let maxCacheSizeBytes: Int = 50 * 1024 * 1024

    // MARK: - Properties

    private let cacheDirectoryURL: URL
    private let indexFileURL: URL
    private let queue = DispatchQueue(label: "com.carplay.assistant.offline.cache", attributes: .concurrent)
    private var index: [String: CacheEntry] = [:]
    private let ttl: TimeInterval

    // MARK: - Initialization

    /// Creates an offline cache manager.
    /// - Parameters:
    ///   - directoryName: The subdirectory name within Documents. Defaults to "OfflineCache".
    ///   - ttl: Time-to-live for cached entries. Defaults to 24 hours.
    public init(directoryName: String = "OfflineCache", ttl: TimeInterval = OfflineCacheManager.defaultTTL) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectoryURL = documentsURL.appendingPathComponent(directoryName)
        self.indexFileURL = cacheDirectoryURL.appendingPathComponent("cache_index.json")
        self.ttl = ttl

        createCacheDirectoryIfNeeded()
        loadIndex()
    }

    // MARK: - Public API

    /// Caches a response for a given query.
    /// - Parameters:
    ///   - response: The response text to cache.
    ///   - query: The query string that produced this response.
    ///   - source: The source of the response. Defaults to "claude_api".
    public func cache(response: String, forQuery query: String, source: String = "claude_api") {
        let normalizedQuery = normalizeQuery(query)
        let now = Date()

        let cachedResponse = CachedResponse(
            text: response,
            cachedAt: now,
            expiresAt: now.addingTimeInterval(ttl),
            source: source
        )

        let entry = CacheEntry(
            query: normalizedQuery,
            response: cachedResponse,
            lastAccessedAt: now
        )

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.index[normalizedQuery] = entry
            self.evictIfNeeded()
            self.persistIndex()
        }
    }

    /// Retrieves a cached response for a query, if one exists and has not expired.
    /// - Parameter query: The query to look up.
    /// - Returns: The cached response, or nil if not found or expired.
    public func getCachedResponse(for query: String) -> CachedResponse? {
        let normalizedQuery = normalizeQuery(query)

        var result: CachedResponse?

        queue.sync {
            guard var entry = self.index[normalizedQuery] else { return }

            if entry.response.isExpired {
                return
            }

            entry.lastAccessedAt = Date()
            self.index[normalizedQuery] = entry
            result = entry.response
        }

        if result != nil {
            queue.async(flags: .barrier) { [weak self] in
                self?.persistIndex()
            }
        }

        return result
    }

    /// Removes all cached responses.
    public func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.index.removeAll()
            self.persistIndex()
        }
    }

    /// Returns the approximate size of the cache in bytes.
    /// - Returns: Cache size in bytes.
    public func cacheSize() -> Int {
        var size = 0
        queue.sync {
            if let data = try? JSONEncoder().encode(Array(self.index.values)) {
                size = data.count
            }
        }
        return size
    }

    /// Returns the number of cached entries.
    /// - Returns: Number of entries in the cache.
    public func entryCount() -> Int {
        var count = 0
        queue.sync {
            count = self.index.count
        }
        return count
    }

    /// Removes expired entries from the cache.
    public func purgeExpired() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.index = self.index.filter { !$0.value.response.isExpired || $0.value.response.expiresAt > now }
            self.persistIndex()
        }
    }

    // MARK: - Private

    private func normalizeQuery(_ query: String) -> String {
        query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createCacheDirectoryIfNeeded() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }

    private func loadIndex() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard FileManager.default.fileExists(atPath: self.indexFileURL.path),
                  let data = try? Data(contentsOf: self.indexFileURL),
                  let entries = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
                return
            }
            // Filter out expired entries on load
            self.index = entries.filter { !$0.value.response.isExpired }
        }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }

    /// Evicts least-recently-used entries until cache is under the max size.
    private func evictIfNeeded() {
        guard let data = try? JSONEncoder().encode(Array(index.values)),
              data.count > OfflineCacheManager.maxCacheSizeBytes else {
            return
        }

        // Sort by lastAccessedAt ascending (oldest first) for LRU
        let sorted = index.sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }

        var currentSize = data.count
        for (key, entry) in sorted {
            guard currentSize > OfflineCacheManager.maxCacheSizeBytes else { break }
            if let entryData = try? JSONEncoder().encode(entry) {
                currentSize -= entryData.count
            }
            index.removeValue(forKey: key)
        }
    }
}
