//
//  DiskCacheTests.swift
//  Mattress
//
//  Created by David Mauro on 11/14/14.
//  Copyright (c) 2014 BuzzFeed. All rights reserved.
//

import XCTest

class DiskCacheTests: XCTestCase {

    override func setUp() {
        // Ensure plist on disk is reset
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 0)
        if let path = diskCache.diskPathForPropertyList()?.path {
            try! FileManager.default.removeItem(atPath: path)
        }
    }

    func testDiskPathForRequestIsDeterministic() {
        let url = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url)
        let request2 = URLRequest(url: url)
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        let path = diskCache.diskPath(for: request1)
        XCTAssertNotNil(path, "Path for request was nil")
        XCTAssert(path == diskCache.diskPath(for: request2), "Requests for the same url did not match")
    }

    func testDiskPathsForDifferentRequestsAreNotEqual() {
        let url1 = URL(string: "foo://bar")!
        let url2 = URL(string: "foo://baz")!
        let request1 = URLRequest(url: url1)
        let request2 = URLRequest(url: url2)
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        let path1 = diskCache.diskPath(for: request1)
        let path2 = diskCache.diskPath(for: request2)
        XCTAssert(path1 != path2, "Paths should not be matching")
    }

    func testStoreCachedResponseReturnsTrue() {
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: ["foo" : "bar"])
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
        let success = diskCache.store(cachedResponse: cachedResponse, for: request)
        XCTAssert(success, "Did not save the cached response to disk")
    }

    func testCachedResponseCanBeArchivedAndUnarchivedWithoutDataLoss() {
        // Saw some old reports of keyedArchiver not working well with NSCachedURLResponse
        // so this is just here to make sure things are working on Apple's end
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: ["foo" : "bar"])
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
        diskCache.store(cachedResponse: cachedResponse, for: request)

        let restored = diskCache.cachedResponse(for: request)
        if let restored = restored {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
    }

    func testCacheReturnsCorrectResponseForRequest() {
        let url1 = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url1)
        let cachedResponse1 = cachedResponseWithDataString("hello, world", request: request1, userInfo: ["foo" : "bar"])

        let url2 = URL(string: "foo://baz")!
        let request2 = URLRequest(url: url2)
        let cachedResponse2 = cachedResponseWithDataString("goodbye, cruel world", request: request2, userInfo: ["baz" : "qux"])

        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
        let success1 = diskCache.store(cachedResponse: cachedResponse1, for: request1)
        let success2 = diskCache.store(cachedResponse: cachedResponse2, for: request2)
        XCTAssert(success1 && success2, "The responses did not save properly")

        let restored1 = diskCache.cachedResponse(for: request1)
        if let restored = restored1 {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse1)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
        let restored2 = diskCache.cachedResponse(for: request2)
        if let restored = restored2 {
            assertCachedResponsesAreEqual(response1: restored, response2: cachedResponse2)
        } else {
            XCTFail("Did not get back a cached response from diskCache")
        }
    }

    func testStoredRequestIncrementsDiskCacheSizeByFilesize() {
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: ["foo" : "bar"])
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024 * 1024)
        XCTAssert(diskCache.currentSize == 0, "Current size should start zeroed out")
        diskCache.store(cachedResponse: cachedResponse, for: request)
        if let path = diskCache.diskPath(for: request)?.path {
            let attributes = try! FileManager.default.attributesOfItem(atPath: path)
            if let fileSize = attributes[FileAttributeKey.size] as? NSNumber {
                let size = fileSize.intValue
                XCTAssert(diskCache.currentSize == size, "Disk cache size was not incremented by the correct amount")
            } else {
                XCTFail("Could not get fileSize from attribute")
            }
        } else {
            XCTFail("Did not get a valid path for request")
        }
    }

    func testStoringARequestIncreasesTheRequestCachesSize() {
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: nil)
        XCTAssert(diskCache.requestCaches.count == 0, "Should not start with any request caches")
        diskCache.store(cachedResponse: cachedResponse, for: request)
        XCTAssert(diskCache.requestCaches.count == 1, "requestCaches should be 1")
    }

    func testFilesAreRemovedInChronOrderWhenCacheExceedsMaxSize() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)
        let dataSize = cacheSize/3 + 1

        let url1 = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url1)
        let cachedResponse1 = cachedResponseWithDataOfSize(dataSize, request: request1, userInfo: nil)

        let url2 = URL(string: "bar://baz")!
        let request2 = URLRequest(url: url2)
        let cachedResponse2 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        let url3 = URL(string: "baz://qux")!
        let request3 = URLRequest(url: url3)
        let cachedResponse3 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        diskCache.store(cachedResponse: cachedResponse1, for: request1)
        diskCache.store(cachedResponse: cachedResponse2, for: request2)
        diskCache.store(cachedResponse: cachedResponse3, for: request3) // This should cause response1 to be removed

        let requestCaches = [diskCache.hash(forURLString: url2.absoluteString)!, diskCache.hash(forURLString: url3.absoluteString)!]
        XCTAssert(diskCache.requestCaches == requestCaches, "Request caches did not match expectations")
    }

    func testPlistIsUpdatedAfterStoringARequest() {
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let cachedResponse = cachedResponseWithDataString("hello, world", request: request, userInfo: nil)
        diskCache.store(cachedResponse: cachedResponse, for: request)

        let data = NSKeyedArchiver.archivedData(withRootObject: cachedResponse)
        let expectedSize = data.count
        let expectedRequestCaches = diskCache.requestCaches
        if let plistPath = diskCache.diskPathForPropertyList()?.path {
            if FileManager.default.fileExists(atPath: plistPath) {
                if let dict = NSDictionary(contentsOfFile: plistPath) {
                    if let currentSize = dict.value(forKey: DiskCache.DictionaryKeys.maxCacheSize) as? Int {
                        XCTAssert(currentSize == expectedSize, "Current size did not match expected value")
                    } else {
                        XCTFail("Plist did not have currentSize property")
                    }
                    if let requestCaches = dict.value(forKey: DiskCache.DictionaryKeys.requestsFilenameArray) as? [String] {
                        XCTAssert(requestCaches == expectedRequestCaches, "Request caches did not match expected value")
                    } else {
                        XCTFail("Plist did not have requestCaches property")
                    }
                }
            } else {
                XCTFail("Could not find plist")
            }
        } else {
            XCTFail("Could not get plist path")
        }
    }

    func testDiskCacheRestoresPropertiesFromPlist() {
        var expectedRequestCaches: [String] = []
        var expectedSize = 0
        autoreleasepool { [unowned self] in
            let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
            let url = URL(string: "foo://bar")!
            let request = URLRequest(url: url)
            let cachedResponse = self.cachedResponseWithDataString("hello, world", request: request, userInfo: nil)
            diskCache.store(cachedResponse: cachedResponse, for: request)
            expectedRequestCaches = diskCache.requestCaches
            expectedSize = diskCache.currentSize
        }
        let newDiskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024)
        XCTAssert(newDiskCache.currentSize == expectedSize, "Size property did not match expectations")
        XCTAssert(newDiskCache.requestCaches == expectedRequestCaches, "RequestCaches did not match expectations")
    }

    func testRequestCacheIsRemovedFromDiskAfterTrim() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)
        let dataSize = cacheSize/3 + 1

        let url1 = URL(string: "foo://bar")!
        let request1 = URLRequest(url: url1)
        let cachedResponse1 = cachedResponseWithDataOfSize(dataSize, request: request1, userInfo: nil)
        let pathForResponse = (diskCache.diskPath(for: request1)?.path)!

        let url2 = URL(string: "bar://baz")!
        let request2 = URLRequest(url: url2)
        let cachedResponse2 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        let url3 = URL(string: "baz://qux")!
        let request3 = URLRequest(url: url3)
        let cachedResponse3 = cachedResponseWithDataOfSize(dataSize, request: request2, userInfo: nil)

        diskCache.store(cachedResponse: cachedResponse1, for: request1)
        diskCache.store(cachedResponse: cachedResponse2, for: request2)
        var isFileOnDisk = FileManager.default.fileExists(atPath: pathForResponse)
        XCTAssert(isFileOnDisk, "File should be on disk")
        diskCache.store(cachedResponse: cachedResponse3, for: request3) // This should cause response1 to be removed
        isFileOnDisk = FileManager.default.fileExists(atPath: pathForResponse)
        XCTAssertFalse(isFileOnDisk, "File should no longer be on disk")
    }

    func testiOS7CanSaveCachedResponse() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let dataSize = cacheSize/3 + 1
        let diskCache = DiskCacheiOS7(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)

        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let userInfo = ["foo" : "bar"]
        let cachedResponse = cachedResponseWithDataOfSize(dataSize, request: request, userInfo: userInfo)
        diskCache.store(cachedResponse: cachedResponse, for: request)
        let basePath = (diskCache.diskPath(for: request)?.path)!

        let responsePath = diskCache.hashForResponse(from: basePath)
        let dataPath = diskCache.hashForData(from: basePath)
        let userInfoPath = diskCache.hashForUserInfo(from: basePath)

        XCTAssert(FileManager.default.fileExists(atPath: responsePath), "Response file should be on disk")
        XCTAssert(FileManager.default.fileExists(atPath: dataPath), "Data file should be on disk")
        XCTAssert(FileManager.default.fileExists(atPath: userInfoPath), "User Info file should be on disk")
    }

    func testiOS7CanRestoreCachedResponse() {
        let cacheSize = 1024 * 1024 // 1MB so dataSize dwarfs the size of encoding the object itself
        let dataSize = cacheSize/3 + 1
        let diskCache = DiskCacheiOS7(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: cacheSize)

        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let userInfo = ["foo" : "bar"]
        let cachedResponse = cachedResponseWithDataOfSize(dataSize, request: request, userInfo: userInfo)
        diskCache.store(cachedResponse: cachedResponse, for: request)

        if let response = diskCache.cachedResponse(for: request) {
            assertCachedResponsesAreEqual(response1: response, response2: cachedResponse)
        } else {
            XCTFail("Could not retrieve cached response")
        }
    }

    func testClearCacheRemovesAnyExistingRequests() {
        let url = URL(string: "foo://bar")!
        let request = URLRequest(url: url)
        let userInfo = ["foo" : "bar"]
        let dataSize = 1
        let cachedResponse = cachedResponseWithDataOfSize(dataSize, request: request, userInfo: userInfo)
        let diskCache = DiskCache(path: "test", searchPathDirectory: .documentDirectory, maxCacheSize: 1024*1024)
        diskCache.store(cachedResponse: cachedResponse, for: request)
        diskCache.clearCache()
        XCTAssertFalse(diskCache.hasCache(for: request))
    }

    // Mark: - Test Helpers

    func assertCachedResponsesAreEqual(response1 : CachedURLResponse, response2: CachedURLResponse) {
        XCTAssert(response1.data == response2.data, "Data did not match")
        XCTAssert(response1.response.url == response2.response.url, "Response did not match")
        if response1.userInfo != nil && response2.userInfo != nil {
            XCTAssert(response1.userInfo!.description == response2.userInfo!.description, "userInfo didn't match")
        } else if !(response1.userInfo == nil && response2.userInfo == nil) {
            XCTFail("userInfo did not match")
        }
    }

    func cachedResponseWithDataString(_ dataString: String, request: URLRequest, userInfo: [AnyHashable: Any]?) -> CachedURLResponse {
        let data = dataString.data(using: String.Encoding.utf8, allowLossyConversion: false)!
        let response = URLResponse(url: request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: nil)
        let cachedResponse = CachedURLResponse(response: response, data: data, userInfo: userInfo, storagePolicy: .allowed)
        return cachedResponse
    }

    func cachedResponseWithDataOfSize(_ dataSize: Int, request: URLRequest, userInfo: [AnyHashable: Any]?) -> CachedURLResponse {
        let bytes: [UInt32] = Array(repeating: 1, count: dataSize)
        let data = Data(bytes: bytes, count: dataSize)
        let response = URLResponse(url: request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: nil)
        let cachedResponse = CachedURLResponse(response: response, data: data, userInfo: userInfo, storagePolicy: .allowed)
        return cachedResponse
    }
}

class DiskCacheiOS7: DiskCache {
    override var isAtLeastiOS8: Bool {
        return false
    }
}
