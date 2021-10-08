//
//  AllocationTests.swift
//  
//
//  Created by Hristo Doichev on 10/8/21.
//

import XCTest
@testable import Allocator

final class AllocatorTests: XCTestCase {
    let FREE_MEMORY_COUNT_8GB: Int = 8*1024*1024*1024
    let FREE_MEMORY_COUNT_4GB: Int = 4*1024*1024*1024
    let FREE_MEMORY_COUNT_1GB: Int = 4*1024*1024*1024
    let FREE_MEMORY_COUNT_100MB: Int = 100*1024*1024
    let FREE_MEMORY_COUNT_10MB: Int = 10*1024*1024

    func testAllocateAll() {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_4GB)
        var allMemory = allocator.allocate(FREE_MEMORY_COUNT_4GB)
        XCTAssertNotNil(allMemory, "Should have allocated an object (Chunks)")
        XCTAssertEqual(allMemory?.allocatedCount, FREE_MEMORY_COUNT_4GB, "Should be all of the space")
        XCTAssertEqual(allocator.freeByteCount, 0, "Should have no more space to allocate")
        allMemory?.deallocate(allocator)
        XCTAssertEqual(allMemory?.allocatedCount, 0, "Should contain no space at all")
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_4GB, "Should have all of the space available")
    }
    func testAllocateMany_AllSpace() {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_10MB)
        var allocated = [Allocator.Chunks]()
        
        for _ in 0..<10240 {
            let c = allocator.allocate(1024)
            XCTAssertNotNil(c, "Should have allocated an object (Chunks)")
            allocated.append(c!)
        }
        let allocated_count = allocated.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count}}
        XCTAssertEqual(allocated_count, FREE_MEMORY_COUNT_10MB, "Should be all of the free space")
        XCTAssertEqual(allocator.freeByteCount, 0, "Should have no more space to allocate")
        for i in 0..<allocated.count { allocated[i].deallocate(allocator) }
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_10MB, "Should have all of the space available")
    }
    func testSegmentation() {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_10MB)
        var allocated = [Allocator.Chunks]()
        
        for _ in 0..<10240 {
            let c = allocator.allocate(1024)
            XCTAssertNotNil(c, "Should have allocated an object (Chunks)")
            allocated.append(c!)
        }
        // Deallocate every other item
        for i in 0..<allocated.count {
            if (i % 2) == 1 { allocated[i].deallocate(allocator) }
        }
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_10MB / 2, "Should have half of the space available")
        // The available space is segmented in 1024 chunks. Try to allocate all of that space in a single operation.
        var large = allocator.allocate(FREE_MEMORY_COUNT_10MB / 2)
        XCTAssertNotNil(large)
        large?.deallocate(allocator)
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_10MB / 2, "Should have half of the space available")
        for i in 0..<allocated.count { allocated[i].deallocate(allocator) }
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_10MB, "Should have half of the space available")
    }
    /// Create segmentation using different size small allocations and then try to create one large allocation
    func testSegmentation2() {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_10MB)
        var allocated = [Allocator.Chunks]()
        // This will allocate a total of 10485120 and 2560 are left free
        for s in [64,128,256,512,1024,2048] {
            for _ in 0..<2600 {
                let c = allocator.allocate(s)
                XCTAssertNotNil(c, "Should have allocated an object (Chunks)")
                allocated.append(c!)
            }
        }
        XCTAssertEqual(allocator.freeByteCount, 2560, "Should have some of the space available")
        // Deallocate every other item
        for i in 0..<allocated.count {
            if (i % 2) == 1 { allocated[i].deallocate(allocator) }
        }
        XCTAssertEqual(allocator.freeByteCount, 5244160, "Should have half space available")
        var large = allocator.allocate(5244160)
        XCTAssertNotNil(large)
        XCTAssertEqual(allocator.freeByteCount, 0, "Should have no space available")
        large?.deallocate(allocator)
        XCTAssertEqual(allocator.freeByteCount, 5244160, "Should have half space available")
    }
    func testAllocateAllWithOverhead() {
        let overhead = MemoryLayout<Allocator.Chunk>.size
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_4GB)
        var a = allocator.allocate(FREE_MEMORY_COUNT_4GB / 2, overhead)
        XCTAssertNotNil(a, "Should have allocated an object (Chunks)")
        let allocOverhead = overhead * a!.count
        
        XCTAssertGreaterThanOrEqual(a!.allocatedCount, allocOverhead + (FREE_MEMORY_COUNT_4GB / 2), "Should be the space + overhead per page")
        XCTAssertLessThanOrEqual(allocator.freeByteCount, (FREE_MEMORY_COUNT_4GB / 2) - allocOverhead, "Should have no more space to allocate")
        a?.deallocate(allocator)
        XCTAssertEqual(a?.allocatedCount, 0, "Should contain no space at all")
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_4GB, "Should have all of the space available")
    }
}
