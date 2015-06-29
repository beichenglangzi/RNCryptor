//
//  Decryptor.swift
//  RNCryptor
//
//  Created by Rob Napier on 6/27/15.
//  Copyright © 2015 Rob Napier. All rights reserved.
//

import CommonCrypto

final class KeyDecryptorV3: DataSinkType, DecryptorType {
    // Buffer -> Tee -> HMAC
    //               -> Cryptor -> Sink

    static let version = UInt8(3)
    static let options = UInt8(0)
    static let headerLength: Int = sizeofValue(version) + sizeofValue(options) + IVSize

    private var bufferSink: BufferSink
    private var hmacSink: HMACSink
    private var cryptor: Cryptor
    private var pendingHeader: [UInt8]?

    init?(encryptionKey: [UInt8], hmacKey: [UInt8], header: [UInt8], sink: DataSinkType) {
        guard encryptionKey.count == KeySize &&
            hmacKey.count == KeySize &&
            header.count == KeyDecryptorV3.headerLength &&
            header[0] == KeyDecryptorV3.version &&
            header[1] == KeyDecryptorV3.options
            else {
                // Shouldn't have to set these, but Swift 2 requires it
                self.bufferSink = BufferSink(capacity: 0, sink: NullSink())
                self.hmacSink = HMACSink(key: [])
                self.cryptor = Cryptor(operation: CCOperation(kCCDecrypt), key: [], IV: [], sink: NullSink())
                return nil
        }

        self.pendingHeader = header

        let iv = Array(header[2..<18])
        self.cryptor = Cryptor(operation: CCOperation(kCCDecrypt), key: encryptionKey, IV: iv, sink: sink)
        self.hmacSink = HMACSink(key: hmacKey)
        let teeSink = TeeSink(self.cryptor, self.hmacSink)
        self.bufferSink = BufferSink(capacity: HMACSize, sink: teeSink)
    }

    func put(data: UnsafeBufferPointer<UInt8>) throws {
        if let pendingHeader = self.pendingHeader {
            try self.hmacSink.put(pendingHeader)
            self.pendingHeader = nil
        }
        try bufferSink.put(data) // Cryptor -> HMAC -> sink
    }

    func finish() throws {
        try self.cryptor.finish()
        let hash = self.hmacSink.final()
        if hash != self.bufferSink.array {
            throw Error.HMACMismatch
        }
    }
}