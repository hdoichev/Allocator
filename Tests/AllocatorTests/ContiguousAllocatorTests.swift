import XCTest
@testable import Allocator

final class ContiguousAllocatorTests: XCTestCase {
    let FREE_MEMORY_COUNT_8GB: Int = 8*1024*1024*1024
    let FREE_MEMORY_COUNT_4GB: Int = 4*1024*1024*1024
    let FREE_MEMORY_COUNT_1GB: Int = 4*1024*1024*1024
    let FREE_MEMORY_COUNT_100MB: Int = 100*1024*1024
    let FREE_MEMORY_COUNT_10MB: Int = 10*1024*1024

    func testAllMemAllocate() throws {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_4GB)
        let allMemory = allocator.allocate(contiguous: FREE_MEMORY_COUNT_4GB)
        XCTAssertNotNil(allMemory, "All memory allocated")
        XCTAssertNil(allocator.allocate(contiguous: 10), "All memory is already used up")
        allocator.deallocate(allMemory!)
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_4GB, "All memory is available")
    }
    func testAllMemAllocate_2() throws {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_1GB)
        let h1 = allocator.allocate(contiguous: FREE_MEMORY_COUNT_1GB / 2)
        let h2 = allocator.allocate(contiguous: FREE_MEMORY_COUNT_1GB / 2)
        XCTAssertNotNil(h1)
        XCTAssertNotNil(h2)
        allocator.deallocate(h1!)
        XCTAssertEqual(allocator.freeByteCount, FREE_MEMORY_COUNT_1GB/2)
    }
    func testManySmallAllocations_16bytes() {
        let allocator = Allocator(capacity: FREE_MEMORY_COUNT_10MB)
        let sizes: [Int] = [32, 64, 128, 256]
        for s in sizes {
            var allocated = Allocator.Chunks()
            let avaiableByteCount = allocator.freeByteCount
            for n in 0..<avaiableByteCount/s {
                let e = allocator.allocate(contiguous: s)
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
