import Foundation

public class InMemoryCache<T> {
    private struct CacheEntry {
        let value: T
        let expiry: Date
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let queue = DispatchQueue(label: "com.flightabove.cache", attributes: .concurrent)
    
    public init() {}
    
    public func get(_ key: String) -> T? {
        return queue.sync {
            guard let entry = cache[key], entry.expiry > Date() else {
                cache.removeValue(forKey: key)
                return nil
            }
            return entry.value
        }
    }
    
    public func set(_ key: String, value: T, ttlSeconds: TimeInterval) {
        queue.async(flags: .barrier) {
            let expiry = Date().addingTimeInterval(ttlSeconds)
            self.cache[key] = CacheEntry(value: value, expiry: expiry)
        }
    }
    
    public func remove(_ key: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: key)
        }
    }
    
    public func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
        }
    }
}

