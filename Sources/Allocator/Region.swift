//
//  File.swift
//  
//
//  Created by Hristo Doichev on 10/7/21.
//

import Foundation

extension Allocator.Region {
    /// Add free space to the region. Split the provided space into the region stride chunks
    ///
    /// - parameter freeChunk: The total free space provided to the region. Must be a multiple of size.
    ///
    mutating func addFreeSpace(_ freeChunk: Allocator.Chunk) {
        guard (freeChunk.count % size) == 0 else { fatalError("Invalid chunk byte count: \(freeChunk.count) != \(size * pageSize)")}
//        for i in stride(from: 0, through: freeChunk.count - size, by: size) {
        for i in stride(from: freeChunk.count - size, through: 0, by: -size) {
            free.append(Allocator.Chunk(address: freeChunk.address + i, count: size))
//            free.insert(Allocator.Chunk(address: freeChunk.address + i, count: size), orderedBy: \.address)
        }
    }
    /// Deallocate a given chunk and make it available for reuse.
    ///
    /// - parameter chunk: Describes the chunk of space.
    mutating func deallocate(_ chunk: Allocator.Chunk) {
        guard chunk.count == size else { fatalError("Invalid chunk byte count: \(chunk.count) != \(size)") }
//        free.insert(chunk, orderedBy: \.address)
        free.append(chunk)
    }
}
