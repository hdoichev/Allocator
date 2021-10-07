import XCTest
@testable import Allocator

final class AllocatorTests: XCTestCase {
    let FREE_MEMORY_COUNT_8GB: UInt64 = 8*1024*1024*1024
    let FREE_MEMORY_COUNT_4GB: UInt64 = 4*1024*1024*1024
    let FREE_MEMORY_COUNT_1GB: UInt64 = 4*1024*1024*1024
    let FREE_MEMORY_COUNT_100MB: UInt64 = 100*1024*1024
    let FREE_MEMORY_COUNT_10MB: UInt64 = 10*1024*1024

    func testAllMemAllocate() throws {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_4GB)
        let allMemory = allocator.allocate(count: FREE_MEMORY_COUNT_4GB)
        XCTAssertNotNil(allMemory, "All memory allocated")
        XCTAssertNil(allocator.allocate(count:10), "All memory is already used up")
        allocator.deallocate(allMemory!)
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_4GB, "All memory is available")
    }
    func testAllMemAllocate_2() throws {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_1GB)
        let h1 = allocator.allocate(count: FREE_MEMORY_COUNT_1GB / 2)
        let h2 = allocator.allocate(count: FREE_MEMORY_COUNT_1GB / 2)
        XCTAssertNotNil(h1)
        XCTAssertNotNil(h2)
        allocator.deallocate(h1!)
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_1GB/2)
    }
    func testManySmallAllocations_16bytes() {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_10MB)
        let sizes: [UInt64] = [16, 32, 64, 128, 256]
        for s in sizes {
            var allocated = Allocator.Chunks()
            for n in 0..<allocator.freeByteCount/s {
                let e = allocator.allocate(count: s)
                XCTAssertNotNil(e)
                if let e = e {
                    allocated.append(e)
                } else {
                    print(n, "Failed")
                    break
                }
            }
            XCTAssertEqual(allocator.freeByteCount, 0, "All memory is used")
            allocated.forEach { allocator.deallocate($0) }
            XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_10MB, "All memory is avaiable")
        }
    }
}
