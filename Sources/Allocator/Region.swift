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
    /// - parameter freeChunk: The total free space provided to the region. Must be a multiple of elementStride.
    ///
    mutating func addFreeSpace(_ freeChunk: Allocator.Chunk) {
        guard (freeChunk.count % elementStride) == 0 else { fatalError("Invalid chunk byte count: \(freeChunk.count) != \(elementStride * pageSize)")}
//        for i in stride(from: 0, through: freeChunk.count - elementStride, by: elementStride) {
        for i in stride(from: freeChunk.count - elementStride, through: 0, by: -elementStride) {
            free.append(Allocator.Chunk(address: freeChunk.address + i, count: elementStride))
//            free.insert(Allocator.Chunk(address: freeChunk.address + i, count: elementStride), orderedBy: \.address)
        }
    }
    /// Deallocate a given chunk and make it available for reuse.
    ///
    /// - parameter chunk: Describes the chunk of space.
    mutating func deallocate(_ chunk: Allocator.Chunk) {
        guard chunk.count == elementStride else { fatalError("Invalid chunk byte count: \(chunk.count) != \(elementStride)") }
//        free.insert(chunk, orderedBy: \.address)
        free.append(chunk)
    }
}
