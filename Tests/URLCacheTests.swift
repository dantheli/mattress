//
//  URLCacheTests.swift
//  Mattress
//
//  Created by David Mauro on 11/13/14.
//  Copyright (c) 2014 BuzzFeed. All rights reserved.
//

import XCTest

private let url = URL(string: "foo://bar")!
private let TestDirectory = "test"

class MockCacher: WebViewCacher {
    override func mattressCacheURL(_ url: URL,
                                   loadedHandler: @escaping WebViewLoadedHandler,
                                   completionHandler: @escaping WebViewCacherCompletionHandler,
                                   failureHandler: @escaping (Error) -> ()) {}
}

class URLCacheTests: XCTestCase {

    func testRequestShouldBeStoredInMattress() {
        let mutableRequest = URLRequest(url: url)
        Foundation.URLProtocol.setProperty(true, forKey: MattressCacheRequestPropertyKey, in: mutableRequest as! NSMutableURLRequest)
        XCTAssert(URLCache.requestShouldBeStoredInMattress(mutableRequest), "")
    }

    func testValidMattressResponseGoesToMattressDiskCache() {
        let mutableRequest = URLRequest(url: url)
        Foundation.URLProtocol.setProperty(true, forKey: MattressCacheRequestPropertyKey, in: mutableRequest as! NSMutableURLRequest)

        var didCallMock = false
        let cache = makeMockURLCache()
        cache.mockDiskCache.storeCacheCalledHandler = {
            didCallMock = true
        }
        let response = makeValidCachedResponseForRequest(mutableRequest)
        cache.storeCachedResponse(response, for: mutableRequest)
        XCTAssertTrue(didCallMock, "Disk cache storage method was not called")
    }

    func testInvalidMattressResponseDoesNotGoToMattressDiskCache() {
        let mutableRequest = URLRequest(url: url)
        Foundation.URLProtocol.setProperty(true, forKey: MattressCacheRequestPropertyKey, in: mutableRequest as! NSMutableURLRequest)

        var didCallMock = false
        let cache = makeMockURLCache()
        cache.mockDiskCache.storeCacheCalledHandler = {
            didCallMock = true
        }
        let response = CachedURLResponse()
        cache.storeCachedResponse(response, for: mutableRequest)
        XCTAssertFalse(didCallMock, "Disk cache storage method was not called")
    }

    func testStandardRequestDoesNotGoToMattressDiskCache() {
        // Ensure plist on disk is reset
        let diskCache = DiskCache(path: TestDirectory, searchPathDirectory: .documentDirectory, maxCacheSize: 0)
        if let path = diskCache.diskPathForPropertyList()?.path {
            try! FileManager.default.removeItem(atPath: path)
        }

        let mutableRequest = URLRequest(url: url)

        var didCallMock = false
        let cache = makeMockURLCache()
        cache.mockDiskCache.storeCacheCalledHandler = {
            didCallMock = true
        }
        let response = CachedURLResponse()
        cache.storeCachedResponse(response, for: mutableRequest)
        XCTAssertFalse(didCallMock, "Disk cache storage method was called")
    }

    func testCachedResponseIsRetriedFromMattressDiskCache() {
        let request = URLRequest(url: url)
        let cachedResponse = CachedURLResponse()

        let cache = makeMockURLCache()
        cache.mockDiskCache.retrieveCacheCalledHandler = { request in
            return cachedResponse
        }
        let response = cache.cachedResponse(for: request)
        if let response = response {
            XCTAssert(response == cachedResponse, "Response did not match")
        } else {
            XCTFail("No response returned from cache")
        }
    }

    func testMattressRequestGeneratesWebViewCacher() {
        let cache = makeURLCache()
        XCTAssert(cache.cachers.count == 0, "Cache should not start with any cachers")
        cache.diskCacheURL(url, loadedHandler: { webView in
            return true
        })
        XCTAssert(cache.cachers.count == 1, "Should have created a single WebViewCacher")
    }

    func testGettingWebViewCacherResponsibleForARequest() {
        let request = URLRequest(url: url)
        let cacher1 = SourceCache()
        let cacher2 = WebViewCacher()

        let cache = makeURLCache()
        cache.cachers.append(cacher1)
        cache.cachers.append(cacher2)
        if let source = cache.webViewCacherOriginatingRequest(request) {
            XCTAssert(source == cacher1, "Returned the incorrect cacher")
        } else {
            XCTFail("No source cacher found")
        }
    }

    func testCachingARequestToTheStandardCacheAlsoUpdatesTheRequestInTheMattressCacheIfItWasAlreadyStoredOnDisk() {
        // Ensure plist on disk is reset
        let diskCache = DiskCache(path: TestDirectory, searchPathDirectory: .documentDirectory, maxCacheSize: 0)
        if let path = diskCache.diskPathForPropertyList()?.path {
            try! FileManager.default.removeItem(atPath: path)
        }

        let cache = MockURLCacheWithMockDiskCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil,
            mattressDiskCapacity: 1024 * 1024, mattressDiskPath: nil, mattressSearchPathDirectory: .documentDirectory, isOfflineHandler: {
                return false
        })

        // Make sure the request has been stored once
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let cachedResponse = makeValidCachedResponseForRequest(request)
        cache.mockDiskCache.storeCachedResponseOnSuper(cachedResponse, forRequest: request)

        var didCall = false
        cache.mockDiskCache.storeCacheCalledHandler = {
            didCall = true
        }

        cache.storeCachedResponse(cachedResponse, for: request)
        XCTAssert(didCall, "The Mattress disk cache storage method was not called")
    }

    // Mark: - Helpers

    func makeValidCachedResponseForRequest(_ request: URLRequest) -> CachedURLResponse {
        let url = request.url ?? URL(string: "")!
        let data = "hello, world".data(using: String.Encoding.utf8, allowLossyConversion: false)!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return CachedURLResponse(response: response, data: data, userInfo: nil, storagePolicy: .allowed)
    }

    func makeURLCache() -> URLCache {
        return URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil, mattressDiskCapacity: 0,
            mattressDiskPath: nil, mattressSearchPathDirectory: .documentDirectory, isOfflineHandler: nil)
    }

    func makeMockURLCache() -> MockURLCacheWithMockDiskCache {
        return MockURLCacheWithMockDiskCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil, mattressDiskCapacity: 0,
            mattressDiskPath: nil, mattressSearchPathDirectory: .documentDirectory, isOfflineHandler: nil)
    }
}

// Mark: - An ode to Xcode being the worst -OR- locally scoped subclasses are supposed to work but don't

class SourceCache: WebViewCacher {
    override func didOriginateRequest(_ request: URLRequest) -> Bool {
        return true
    }
}

class MockDiskCache: DiskCache {
    var storeCacheCalledHandler: (() -> ())?
    var retrieveCacheCalledHandler: ((_ request: URLRequest) -> (CachedURLResponse?))?

    func storeCachedResponseOnSuper(_ cachedResponse: CachedURLResponse, forRequest request: URLRequest) -> Bool {
        return super.store(cachedResponse: cachedResponse, for: request)
    }

    override func store(cachedResponse: CachedURLResponse, for request: URLRequest) -> Bool {
        storeCacheCalledHandler?()
        return true
    }

    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        if let handler = retrieveCacheCalledHandler {
            return handler(request)
        }
        return nil
    }
}
class MockURLCacheWithMockDiskCache: URLCache {
    var mockDiskCache: MockDiskCache {
        return diskCache as! MockDiskCache
    }

    override init(memoryCapacity: Int, diskCapacity: Int, diskPath path: String?, mattressDiskCapacity: Int,
        mattressDiskPath mattressPath: String?, mattressSearchPathDirectory searchPathDirectory: FileManager.SearchPathDirectory, isOfflineHandler: (() -> Bool)?)
    {
        super.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: path, mattressDiskCapacity: mattressDiskCapacity,
            mattressDiskPath: mattressPath, mattressSearchPathDirectory: searchPathDirectory, isOfflineHandler: isOfflineHandler)

        diskCache = MockDiskCache(path: TestDirectory, searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
    }
}

