//
//  Data+Crypto.swift
//  Mattress
//
//  Created by Kevin Lord on 5/22/15.
//  Copyright (c) 2015 BuzzFeed. All rights reserved.
//

import Foundation
import CommonCrypto

extension Data {
    func mattress_hexString() -> String {
        return self.reduce("", { $0 + String(format: "%02x", $1) })
    }

    func mattress_MD5() -> Data {
        let resultPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(CC_MD5_DIGEST_LENGTH))
        
        let bytesPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        copyBytes(to: bytesPointer, count: count)
        
        CC_MD5(bytesPointer, CC_LONG(count), resultPointer)
        return Data(bytesNoCopy: resultPointer, count: Int(CC_MD5_DIGEST_LENGTH), deallocator: .free)
    }

    func mattress_SHA1() -> Data {
        let resultPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(CC_SHA1_DIGEST_LENGTH))
        let bytesPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        copyBytes(to: bytesPointer, count: count)
        
        CC_SHA1(bytesPointer, CC_LONG(count), resultPointer)
        return Data(bytesNoCopy: resultPointer, count: Int(CC_SHA1_DIGEST_LENGTH), deallocator: .free)
    }
}
