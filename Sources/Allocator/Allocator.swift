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
public class Allocator {
    let MEMORY_ALIGNMENT: Int = 8
    let REGION_PAGE_DEFRAG_THRESHOLD: Int = 5
    ///
    enum Flags: Int {
        case None = 0
        case Root
    }
    ///
    public struct Chunk {
        public let address: Int
        public let count: Int
        let flags: Flags
        public init() {
            address = Int.max
            count = 0
            flags = .None
        }
        init(address: Int, count: Int, flags: Flags) {
            self.address = address
            self.count = count
            self.flags = flags
        }
        public var isValid: Bool { return address != Int.max && count != 0 }
    }
    ///
    public typealias Chunks = ContiguousArray<Chunk>
    var _free = Chunks()
    let _sumOfLowerRegionsSizes: ContiguousArray<Int>
    var _defragged: Bool = false
    var _deallocsCount: Int = 0
    var _defragesCount: Int = 0
    var _totalDeallocatedByteCount: Int = 0
    ///
    public var totalDeallocatedByteCount: Int { return _totalDeallocatedByteCount }
    public var totalDeallocsCount: Int { return _deallocsCount }
    public var defragsCount: Int { return _defragesCount }
    
    public var freeChunksCount: Int { return _regions.reduce(_free.count) { return $0 + $1.free.count } }
    public var freeByteCount: Int { return _regions.reduce(_free.reduce(0) { return $0 + $1.count}) { return $0 + $1.free.reduce(0, { $0 + $1.count  })  }}
    ///
    struct Region {
        let elementStride: Int
        let pageSize: Int
        var free: Chunks
    }
    typealias Regions = ContiguousArray<Region>
    var _regions =  Regions()
    ///
    public init(capacity: Int, start address: Int = 0) {
        _free.append(Chunk(address: address, count: capacity, flags: .Root))
        let REGION_PAGE_BYTE_COUNT:Int = 8*1024
        // Init regions by count size
        let p:ContiguousArray<Int> =
        [      32,       64,      128,       256,
              512,     1024,     2048,      4096,
             8192,    16384,    32768,     65536,
         128*1024, 256*1024, 512*1024, 1024*1024]
        _sumOfLowerRegionsSizes = p.sunOfLowerElements()
        p.forEach {
            _regions.append(Region(elementStride: $0,
                                   pageSize: (REGION_PAGE_BYTE_COUNT > $0) ? REGION_PAGE_BYTE_COUNT / $0: 1,
                                   free: Chunks()))
        }
    }
    /// TODO: is this needed???
    static func calculateRegionPageSize(_ capacity: Int) -> Int {
        let l = log2(Double(capacity))
        let computed = Int(pow(2.0, 1.0 + Double(Int(l)/8)))
        return (computed >= 8) ? computed: 8
    }
    ///
    func getChunk(from region: Int) -> Chunk? {
        guard _regions[region].free.isEmpty == true else { return _regions[region].free.removeLast() }
        guard let freeChunk = reserveFreeStorage(count: _regions[region].elementStride * _regions[region].pageSize) else {
            return nil /*fatalError("Failed to allocate memory: \(regpos):\(_regions[regpos].maxCount * _regions[regpos].pageSize)")*/}
        if _regions[region].pageSize > 1 {
            _regions[region].addFreeSpace(freeChunk)
            return _regions[region].free.removeLast()
        } else {
            return freeChunk
        }
    }
    ///
    func findBestMatch(_ val:Int, _ overhead: Int) -> Int {
        let c = _regions.findInsertPosition(val, orderedBy: \.elementStride, compare: <)
        guard c < _regions.count else { return c - 1 }
        if c > 1 {
            if _regions[c].elementStride > val && _regions[c-1].elementStride > overhead {
                let upperBound = _regions[c].elementStride - val
                var estimateLowerBound = _sumOfLowerRegionsSizes[c] - (c * overhead)
                estimateLowerBound = estimateLowerBound > val ? estimateLowerBound - val: val - estimateLowerBound
                if upperBound > estimateLowerBound {
                    return c - 1
                }
            }
        }
        return c
    }
    ///
    public func deallocate(chunks: Chunks) {
        chunks.forEach{ deallocate($0) }
    }
    ///
    public func allocate(_ count: Int, _ overhead: Int = 0) -> Chunks? {
        var remaining = count
        var chunksChain = Chunks()
        var bestRegion: Int = 0
        var lookupBestRegion = true
        while remaining > 0 {
            if lookupBestRegion {
                bestRegion = findBestMatch(remaining + overhead, overhead)
            }
            let c = getChunk(from: bestRegion)
            if c == nil {
                // Since there wasn't a chunk avaiable, try to use the next smaller chunk size
                // and keep going down the sizes until there is enough space available or break-out
                // without allocating anything
                guard bestRegion > 0 else { break }
                lookupBestRegion = false // turn off the lookup
                bestRegion -= 1
                // Best region must have more space than the overhead.
                guard _regions[bestRegion].elementStride > overhead else { break }
            } else {
                guard let c = c else { break } // Done. Can not allocate.
                chunksChain.append(c)
                if (remaining + overhead) <= c.count {
                    // the last allocated chunk provides enough space to store all the info
                    remaining = 0
                } else {
                    remaining = remaining.decrementedClampToZero(c.count - overhead)
                }
                if (remaining + overhead) < _regions[bestRegion].elementStride {
                    lookupBestRegion = true // reenable the lookup in case it was turned off.
                }
            }
        }
        guard remaining == 0 else { deallocate(chunks: chunksChain); return nil }
        return chunksChain
    }
    /// Allocate a contiguous chunk.
    ///
    /// - returns nil: if no contiguous chunk can not be found
    ///
    public func allocate(contiguous count: Int) -> Chunk? {
        let regpos = _regions.findInsertPosition(count, orderedBy: \.elementStride, compare: <)
        guard regpos != _regions.count else { return reserveFreeStorage(count: count) }// super.allocate(count: count) }
        guard _regions[regpos].free.isEmpty else { return _regions[regpos].free.removeLast() }
        guard let freeChunk = reserveFreeStorage(count: _regions[regpos].elementStride * _regions[regpos].pageSize) else
        { return nil /*fatalError("Failed to allocate memory: \(regpos):\(_regions[regpos].maxCount * _regions[regpos].pageSize)")*/}
        _regions[regpos].addFreeSpace(freeChunk)
        return _regions[regpos].free.removeLast()
    }
    ///
    public func deallocate(address: Int, count: Int) {
        self.deallocate(Chunk(address: address, count: count, flags: .None))
    }
    ///
    public func deallocate(_ chunk: Chunk) {
        guard chunk.isValid else { return }
        let regpos = _regions.findInsertPosition(chunk.count, orderedBy: \.elementStride, compare: <)
        guard regpos != _regions.count else {
            reclaimFreeStorage(chunk);
            return
        }
        _deallocsCount += 1
        _totalDeallocatedByteCount += chunk.count
        _regions[regpos].deallocate(chunk)
    }
    ///
    func reserveFreeStorage(count: Int) -> Chunk?{
        // Allign free storage size
        let allignedCount = ((count % MEMORY_ALIGNMENT) == 0) ? count:
                                                               ((count/MEMORY_ALIGNMENT)+1) * MEMORY_ALIGNMENT
        var position = _free.findInsertPosition(allignedCount, orderedBy: \.count, compare: <)
        if position == _free.count {
            // Trigger full defrag, looking for memory
            _defragged = false
            defrag(purge: true)
            position = _free.findInsertPosition(allignedCount, orderedBy: \.count, compare: <)
        }
        guard position != _free.count else {
            return nil
        }
        let chunk = _free.remove(at: position)
        
        if chunk.count > allignedCount {
            _free.insert(Chunk(address: chunk.address + allignedCount, count: chunk.count - allignedCount, flags: .Root), orderedBy: \.count)
        }
        return Chunk(address: chunk.address, count: allignedCount, flags: .Root)
    }
    ///
    func reclaimFreeStorage(_ chunk: Chunk) {
        _free.insert(chunk, orderedBy: \.count)
        _defragged = false
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
                curChunk = Chunk(address: curChunk.address, count: curChunk.count+c.count, flags: .Root)
            } else {
                _free.append(curChunk)
//                _free.insertOrderedByCount(curChunk)
                curChunk = c
            }
        }
//        _free.insertOrderedByCount(curChunk)
        _free.append(curChunk)
        _free.sort { $0.count < $1.count }
    }
    ///
    func coalesceRegion(region: inout Region, coalesced: inout Chunks) {
        let pageByteCount = region.pageSize * region.elementStride
        region.free.sort { $0.address < $1.address }
        var start_address = Int.max
        var chunk_count:Int = 0
        
        for e in region.free {
            if start_address == Int.max /*&& e.flags == .Root*/ {
                start_address = e.address
                chunk_count = e.count
            } else {
                if start_address != Int.max && (start_address + chunk_count) == e.address {
                    chunk_count += e.count
                } else {
                    start_address = Int.max
                    chunk_count = 0
                }
            }
            if chunk_count == pageByteCount {
                coalesced.append(Chunk(address: start_address, count: chunk_count, flags: .Root))
                start_address = Int.max
                chunk_count = 0
            }
        }
    }
    ///
    public func defrag(purge: Bool = false) {
        _defragesCount += 1
        for i in 0..<_regions.count {
//            if purge || _regions[i].free.count >= (_regions[i].pageSize * REGION_PAGE_DEFRAG_THRESHOLD) {
            var coalscedChunks = Chunks()
            coalesceRegion(region: &_regions[i], coalesced: &coalscedChunks)
            if coalscedChunks.isEmpty == false {
                var chunksThatRemain = Chunks()
                var pos = 0
                let free_count = _regions[i].free.count
                for chunkToMove in coalscedChunks {
                    _free.append(chunkToMove)
                    _defragged = false
                    _deallocsCount += 1
                    let removeRange = (chunkToMove.address..<chunkToMove.address + chunkToMove.count)
                    while pos != free_count {
                        if removeRange.contains( _regions[i].free[pos].address ) {
                            // skip over consequtive chunks that should be excluded from the current page
                            while pos != free_count && removeRange.contains( _regions[i].free[pos].address ) { pos += 1 }
                            break // found first chunk that is outside the current exclusion range
                        } else {
                            chunksThatRemain.append(_regions[i].free[pos])
                            pos += 1
                        }
                    }
                }
                // move all remaining, if any
                for toRemain in pos..<free_count {
                    chunksThatRemain.append(_regions[i].free[toRemain])
                }
                _regions[i].free = chunksThatRemain
            }
//            }
        }
        guard _defragged == false else { return }
        //
        coalesce()
        //
        _defragged = true
    }
}
