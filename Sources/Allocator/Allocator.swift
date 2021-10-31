//
//  Allocator.swift
//  Allocator
//
//  Created by Hristo Doichev on 9/29/21.
//

import Foundation

/// Allocate chunks of space.
/// Can provide contiguous chunks of space and also space represented by a seried of contiguous chunks.
///
///
public class Allocator: Codable {
    let MEMORY_ALIGNMENT: Int = 8
    ///
    public struct Chunk: Codable {
        public let address: Int
        public let count: Int
        public init() {
            address = Int.max
            count = 0
        }
        public init(address: Int, count: Int) {
            self.address = address
            self.count = count
        }
        public var isValid: Bool { return address != Int.max && count != 0 }
    }
    /// Region contains chunks of the same size.
    /// The stored chunks are not ordered in any way.
    struct Region: Codable {
        let size: Int
        let pageSize: Int
        var free: Chunks = Chunks()
        var coalescedCount: Int = 0
        var distanceFromCoalesced: Int { free.count - coalescedCount }
        var coalesceThreshold: Int
        var shouldCoalesce: Bool { distanceFromCoalesced >= coalesceThreshold }
    }
    ///
    public typealias Chunks = ContiguousArray<Chunk>
    public typealias ChunksDict = [Int: Chunk]
    typealias Regions = ContiguousArray<Region>
    // MARK: - Private Properties
    let _startAddress: Int
    let _endAddress: Int
    var _free = Chunks()
    let _sumOfLowerRegionsSizes: ContiguousArray<Int>
    var _deallocsCount: Int = 0
    var _defragesCount: Int = 0
    var _totalDeallocatedByteCount: Int = 0
    var _regions =  Regions()
    // MARK: - Public Properties
    public var totalDeallocatedByteCount: Int { return _totalDeallocatedByteCount }
    public var totalDeallocsCount: Int { return _deallocsCount }
    public var defragsCount: Int { return _defragesCount }
    
    public var freeChunksCount: Int { return _regions.reduce(_free.count) { $0 + $1.free.count } }
    public var freeByteCount: Int { return _regions.reduce(_free.reduce(0) { $0 + $1.count}) { $0 + $1.free.reduce(0, { $0 + $1.count  })  }}
    ///
    public init(capacity: Int, start address: Int = 0, minimumAllocationSize: Int = 32) {
        _startAddress = address
        _endAddress = (capacity == Int.max) ? capacity - _startAddress: address + capacity
        _free.append(Chunk(address: address, count: capacity))
        let REGION_PAGE_BYTE_COUNT:Int = 1*512
        // Init regions by count size
        var p:ContiguousArray<Int> = ContiguousArray<Int>()
        for i in 0..<16 {
            p.append(minimumAllocationSize * Int(pow(2.0,Double(i))))
        }
        _sumOfLowerRegionsSizes = p.sunOfLowerElements()
        var regpos = 0
        p.forEach {
            _regions.append(Region(size: $0,
                                   pageSize: (REGION_PAGE_BYTE_COUNT > $0) ? REGION_PAGE_BYTE_COUNT / $0: 1,
                                   coalesceThreshold: Int(pow(Double.pi*2, Double((p.count + 0) - regpos)))))
            regpos += 1
        }
    }
    ///
    func getChunk(from region: Int) -> Chunk? {
        guard region < _regions.count else {
            // fetch from the total free memeory.
            return reserveFreeStorage(count: _regions.last!.size)
        }
        if _regions[region].free.isEmpty {
            // got the upper region and get on og its chunks, which converted into two chunks for the current region
            if let c = getChunk(from: region + 1) {
                _regions[region].addFreeSpace(c)
            }
        }
        guard _regions[region].free.isEmpty else { return _regions[region].free.removeLast() }
        return nil
    }
    ///
    func findBestFitRegion(_ val:Int, _ overhead: Int) -> Int {
        let c = _regions.findInsertPosition(val, orderedBy: \.size, compare: <)
        guard c < _regions.count else { return c - 1 }
        if c > 1 {
            if _regions[c].size > val && _regions[c-1].size > overhead {
                let upperBound = _regions[c].size - val
                var estimateLowerBound = _sumOfLowerRegionsSizes[c] - (c * overhead)
                estimateLowerBound = estimateLowerBound > val ? estimateLowerBound - val: val - estimateLowerBound
                if upperBound > estimateLowerBound {
                    return c - 1
                }
            }
        }
        return c
    }
    /// Allocate space in a non contiguous form. The returned Chunks has a combined count
    /// greater than (or equal) to count. The individual chunks can be of different sizes.
    /// When overhead is non 0 for each chunk (in Chunks) an additinal overhead count is added
    /// to the total allocation. In that case it is guaranteed that each chunk will be greater than overhead.
    ///
    ///     var chunks = allocator.allocate(1024)
    ///     print(chunks.reduce(0) { $0 + $1.count })
    ///     print(chunks.allocatedCount) // same as above
    ///     // prints 1024
    ///
    ///     // allocate a total of at least 1024 and add 12 overhead for each chunk
    ///     var chunks = allocator.allocate(1024, 12)
    ///     var total_overhead = chunks.count * 12
    ///     print((chunks.reduce(0) { $0 + $1.count } - total_overhead) >= 1024)
    ///     print((chunks.allocatedCount - total_overhead) > 1024) // same as above
    ///     // prints true
    ///     
    public func allocate(_ count: Int, overhead: Int = 0) -> Chunks? {
        var remaining = count
        var chunksChain = Chunks()
        var bestRegion: Int = 0
        var lookupBestRegion = true
        while remaining > 0 {
            if lookupBestRegion {
                bestRegion = findBestFitRegion(remaining + overhead, overhead)
            }
            let c = getChunk(from: bestRegion)
            if let c = c {
                chunksChain.append(c)
                if (remaining + overhead) <= c.count {
                    // the last allocated chunk provides enough space to store all the info
                    remaining = 0
                } else {
                    remaining = remaining.decrementedClampToZero(c.count - overhead)
                }
                if (remaining + overhead) < _regions[bestRegion].size {
                    lookupBestRegion = true // reenable the lookup in case it was turned off.
                }
            } else {
                // Since there wasn't a chunk avaiable, try to use the next smaller chunk size
                // and keep going down the sizes until there is enough space available or break-out
                // without allocating anything
                guard bestRegion > 0 else { break }
                lookupBestRegion = false // turn off the lookup
                bestRegion -= 1
                // Best region must have more space than the overhead.
                guard _regions[bestRegion].size > overhead else { break }
            }
        }
        guard remaining == 0 else { deallocate(chunks: chunksChain); return nil }
//        print(chunksChain)
        return chunksChain
    }
    /// Allocate a contiguous chunk.
    ///
    /// - returns nil: if contiguous chunk can not be found
    ///
    public func allocate(contiguous count: Int) -> Chunk? {
        let regpos = _regions.findInsertPosition(count, orderedBy: \.size, compare: <)
        guard regpos != _regions.count else { return reserveFreeStorage(count: count) }// super.allocate(count: count) }
        guard _regions[regpos].free.isEmpty else { return _regions[regpos].free.removeLast() }
        guard let freeChunk = reserveFreeStorage(count: _regions[regpos].size * _regions[regpos].pageSize) else
        { return nil /*fatalError("Failed to allocate memory: \(regpos):\(_regions[regpos].maxCount * _regions[regpos].pageSize)")*/}
        _regions[regpos].addFreeSpace(freeChunk)
        return _regions[regpos].free.removeLast()
    }
    ///
    public func deallocate(_ chunk: Chunk) {
        guard chunk.isValid else { return }
        guard chunk.address >= _startAddress && (chunk.address + chunk.count) <= _endAddress else { return }
        _deallocsCount += 1
        _totalDeallocatedByteCount += chunk.count
        let regpos = _regions.findInsertPosition(chunk.count, orderedBy: \.size, compare: <)
        guard regpos != _regions.count else {
            reclaimFreeStorage(chunk);
            return
        }
        _regions[regpos].deallocate(chunk)
        if _regions[regpos].shouldCoalesce {
            coalesce(at: regpos)
        }
    }
    ///
    public func deallocate(chunks: Chunks) {
        chunks.forEach{ deallocate($0) }
    }
    ///
    func reserveFreeStorage(count: Int) -> Chunk?{
        // Allign free storage size
        let allignedCount = ((count % MEMORY_ALIGNMENT) == 0) ? count:
                                                               ((count/MEMORY_ALIGNMENT)+1) * MEMORY_ALIGNMENT
        var position = _free.findInsertPosition(allignedCount, orderedBy: \.count, compare: <)
        if position == _free.count {
            coalesce()
            position = _free.findInsertPosition(allignedCount, orderedBy: \.count, compare: <)
        }
        guard position != _free.count else {
            return nil
        }
        let chunk = _free.remove(at: position)
        
        if chunk.count > allignedCount {
            _free.insert(Chunk(address: chunk.address + allignedCount, count: chunk.count - allignedCount), orderedBy: \.count)
        }
        return Chunk(address: chunk.address, count: allignedCount)
    }
    ///
    func reclaimFreeStorage(_ chunk: Chunk) {
        _free.insert(chunk, orderedBy: \.count)
        _deallocsCount += 1
        _totalDeallocatedByteCount += chunk.count
    }
    ///
    func coalesce() {
        guard _free.isEmpty == false else { return }
        let sorted = _free.sorted { $0.address < $1.address }
        _free.removeAll()
        
        var curChunk = sorted[0]
        sorted.forEach { c in
            guard curChunk.address != c.address else { return } // first element. It is already curChunk
            if curChunk.address+curChunk.count == c.address {
                curChunk = Chunk(address: curChunk.address, count: curChunk.count+c.count)
            } else {
                _free.append(curChunk)
                curChunk = c
            }
        }
        _free.append(curChunk)
        _free.sort { $0.count < $1.count }
    }
    ///
    func coalesce(at position: Int) {
        guard position < _regions.count else { return }
        var chunks = Chunks()
        coalesceRegion(region: &_regions[position], coalesced: &chunks)
        _regions[position].coalescedCount = _regions[position].free.count
        if position + 1 < _regions.count {
            if chunks.isEmpty == false {
                let pup = position + 1
                chunks.forEach { _regions[pup].free.append($0) }
                coalesce(at: pup)
            }
        } else {
            chunks.forEach { reclaimFreeStorage($0) }
        }
    }
    ///
    func coalesceRegion(region: inout Region, coalesced: inout Chunks) {
        region.free.sort { $0.address < $1.address }
        var nonCoalesced = Chunks()
        var lastChunk = Chunk()
        
        for e in region.free {
            if lastChunk.address == Int.max {
                lastChunk = e
            } else {
                if lastChunk.address != Int.max && (lastChunk.address + lastChunk.count) == e.address {
                    coalesced.append(Chunk(address: lastChunk.address, count: 2 * lastChunk.count))
                    lastChunk = Chunk()
                } else {
                    nonCoalesced.append(lastChunk)
                    lastChunk = e
                }
            }
        }
        if lastChunk.address != Int.max {
            nonCoalesced.append(lastChunk)
        }
        region.free = nonCoalesced
    }
    ///
    public func defrag(purge: Bool = false) {
        _defragesCount += 1
        for i in 0..<_regions.count {
            coalesce(at: i)
        }
        //
        coalesce()
    }
}

extension Allocator.Chunk: Hashable {
    public static func == (_ lhs: Allocator.Chunk, _ rhs: Allocator.Chunk) -> Bool {
        return lhs.address == rhs.address && lhs.count == rhs.count
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.address)
    }
}
