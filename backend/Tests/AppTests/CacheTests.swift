import XCTest
@testable import App

final class CacheTests: XCTestCase {
    
    func testCacheSetAndGet() {
        let cache = InMemoryCache<String>()
        
        cache.set("key1", value: "value1", ttlSeconds: 60)
        
        let value = cache.get("key1")
        XCTAssertEqual(value, "value1")
    }
    
    func testCacheExpiry() {
        let cache = InMemoryCache<String>()
        
        cache.set("key1", value: "value1", ttlSeconds: 0.1)
        
        let value1 = cache.get("key1")
        XCTAssertEqual(value1, "value1")
        
        // Wait for expiry
        let expectation = expectation(description: "Cache expiry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let value2 = self.cache.get("key1")
            XCTAssertNil(value2, "Value should be nil after expiry")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCacheRemove() {
        let cache = InMemoryCache<String>()
        
        cache.set("key1", value: "value1", ttlSeconds: 60)
        cache.remove("key1")
        
        let value = cache.get("key1")
        XCTAssertNil(value)
    }
    
    func testCacheClear() {
        let cache = InMemoryCache<String>()
        
        cache.set("key1", value: "value1", ttlSeconds: 60)
        cache.set("key2", value: "value2", ttlSeconds: 60)
        cache.clear()
        
        XCTAssertNil(cache.get("key1"))
        XCTAssertNil(cache.get("key2"))
    }
}

