//
//  Allocator.swift
//  Allocator
//
//  Created by Hristo Doichev on 9/29/21.
//

import Foundation
/// ==========================================
///
///
public class Allocator {
    let DEALLOCS_DEFRAG_TRIGGER: Int = 3_000
    let DEALLOCS_COALESCE_TIRGGER: Int = 3_000
    let MEMORY_ALIGNMENT: UInt64 //= 64*1024
    let REGION_PAGE_DEFRAG_THRESHOLD: UInt64 = 5
    ///
    enum Flags: Int {
        case None = 0
        case Root
    }
    ///
    public struct Chunk {
        public let address: UInt64
        public let count: UInt64
        let flags: Flags
        public init() {
            address = UInt64.max
            count = 0
            flags = .None
        }
        init(address: UInt64, count: UInt64, flags: Flags) {
            self.address = address
            self.count = count
            self.flags = flags
        }
        public var isValid: Bool { return address != UInt64.max && count != 0 }
    }
    ///
    public typealias Chunks = ContiguousArray<Chunk>
    var _free = Chunks()
    var _defragged: Bool = false
    var _deallocsCount: Int = 0
    var _totalDeallocatedByteCount: UInt64 = 0
    ///
    public var totalDeallocatedByteCount: UInt64 { return _totalDeallocatedByteCount }
    public var totalDeallocsCount: Int { return _deallocsCount }
    
    public var freeChunksCount: Int { return _regions.reduce(_free.count) { return $0 + $1.free.count } }
    public var freeByteCount: UInt64 { return _regions.reduce(_free.reduce(0) { return $0 + $1.count}) { return $0 + $1.free.reduce(0, { $0 + $1.count  })  }}
    ///
    struct Region {
        let elementStride: UInt64
        let pageSize: UInt64
        var free: Chunks
        ///
        mutating func addFreeSpace(_ freeChunk: Chunk) {
            guard (freeChunk.count % elementStride) == 0 else { fatalError("Invalid chunk byte count: \(freeChunk.count) != \(elementStride * pageSize)")}
            var cflags = Allocator.Flags.Root
            for i in stride(from: 0, through: freeChunk.count - 1, by: UInt64.Stride(elementStride)) {
                free.append(Chunk(address: freeChunk.address + i, count: elementStride, flags: cflags))
//                free.insert(Chunk(address: freeChunk.address + i, count: maxCount, flags: cflags), orderedBy: \.address)
                cflags = .None
            }
        }
        mutating func deallocate(_ chunk: Chunk) {
            guard chunk.count == elementStride else { fatalError("Invalid Chunk count: \(chunk.count) instead of \(elementStride)") }
//            free.insert(chunk, orderedBy: \.address)
            free.append(chunk)
        }
        mutating func removeAllFree() { free.removeAll() }
        mutating func updateFreeSpace(_ block: (/*maxCount*/UInt64, /*pageSize*/UInt64, inout Chunks)->Void) { block(elementStride, pageSize, &free) }
    }
    typealias Regions = ContiguousArray<Region>
    var _regions =  Regions()
    ///
    public init(capacity: UInt64, start address: UInt64 = 0) {
        _free.append(Chunk(address: address, count: capacity, flags: .Root))
//        REGION_PAGE_BYTE_COUNT = Allocator.calculateRegionPageSize(capacity)
        let PAGE_BYTE_COUNT:UInt64 = 4*1024
        MEMORY_ALIGNMENT = 8
        // Init regions by count size
        let p:[UInt64] =
        [16,    32,     64]//,    128,
//         256,   512,    1024,  2048,
//         4096,  8192,   16384, 32768,
//         65536, 128*1024, 256*1024, 512*1024]
        p.forEach {
            if $0 <= MEMORY_ALIGNMENT {
                _regions.append(Region(elementStride: $0,
                                       pageSize: (PAGE_BYTE_COUNT > $0) ? PAGE_BYTE_COUNT / $0: 1,
                                       free: Chunks()))
            }
        }
    }
    ///
    static func calculateRegionPageSize(_ capacity: UInt64) -> UInt64 {
        let l = log2(Double(capacity))
        let computed = UInt64(pow(2.0, 1.0 + Double(Int(l)/8)))
        return (computed >= 8) ? computed: 8
    }
    ///
    public func allocate(count: UInt64) -> Chunk? {
        let regpos = _regions.findInsertPosition(count, orderedBy: \.elementStride, compare: <)
        guard regpos != _regions.count else { return reserveFreeStorage(count: count) }// super.allocate(count: count) }
        guard _regions[regpos].free.isEmpty else { return _regions[regpos].free.removeLast() }
        guard let freeChunk = reserveFreeStorage(count: _regions[regpos].elementStride * _regions[regpos].pageSize) else
        { return nil /*fatalError("Failed to allocate memory: \(regpos):\(_regions[regpos].maxCount * _regions[regpos].pageSize)")*/}
        _regions[regpos].addFreeSpace(freeChunk)
        return _regions[regpos].free.removeLast()
    }
    ///
    public func deallocate(address: UInt64, count: UInt64) {
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
        /// What should trigger the free space reclamation ???
        if (_deallocsCount % DEALLOCS_DEFRAG_TRIGGER) == 0 {
            self.defrag(purge: true)
        }
    }
    ///
    func reserveFreeStorage(count: UInt64) -> Chunk?{
        // Allign free storage size
        let allignedCount = ((count % MEMORY_ALIGNMENT) == 0) ? count: ((count/MEMORY_ALIGNMENT)+1) * MEMORY_ALIGNMENT
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
    func reclaimFreeStorage(_ chunk: Chunk) {
        _free.insert(chunk, orderedBy: \.count)
        _defragged = false
        _deallocsCount += 1
        _totalDeallocatedByteCount += chunk.count
        if (_deallocsCount % DEALLOCS_COALESCE_TIRGGER) == 0 {
            self.coalesce()
        }
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
    public func defrag(purge: Bool = false) {
        for i in 0..<_regions.count {
            if purge || _regions[i].free.count >= (_regions[i].pageSize * REGION_PAGE_DEFRAG_THRESHOLD) {
                let pageCount = _regions[i].pageSize * _regions[i].elementStride
                _regions[i].free.sort { $0.address < $1.address }
                var start_address = UInt64.max
                var chunk_count:UInt64 = 0
                var pageChunks = Chunks()
                
                for e in _regions[i].free {
                    if start_address == UInt64.max && e.flags == .Root {
                        start_address = e.address
                        chunk_count = e.count
                    } else {
                        if start_address != UInt64.max && (start_address + chunk_count) == e.address {
                            chunk_count += e.count
                        } else {
                            start_address = UInt64.max
                            chunk_count = 0
                        }
                    }
                    if chunk_count == pageCount {
                        pageChunks.append(Chunk(address: start_address, count: chunk_count, flags: .Root))
                        //                        print("Found page: ragion[\(i)] pageCount = \(pageCount)")
                        start_address = UInt64.max
                        chunk_count = 0
                    }
                }
                if pageChunks.isEmpty == false {
                    for chunkToMove in pageChunks {
                        let removeRange = (chunkToMove.address..<chunkToMove.address + chunkToMove.count)
                        _regions[i].free.removeAll { removeRange.contains( $0.address ) }
                        //                        _free.insert(chunkToMove, orderedBy: \.count)
                        // _free will be coalesced later on, so no need to place the chunk in it proper position here.
                        _free.append(chunkToMove)
                        _defragged = false
                        _deallocsCount += 1
                    }
                }
            }
        }
        guard _defragged == false else { return }
        //
        coalesce()
        //
        _defragged = true
    }
}

extension Allocator.Chunks {
    func print(_ header: String) {
        Swift.print(header)
        forEach { Swift.print("Address: ", $0.address, ", Count: ", $0.count) }
    }
}

extension ContiguousArray {
    func findInsertPosition<T:Comparable>(_ value: T, orderedBy keyPath: KeyPath<Element, T>, compare: (T,T)->Bool = (<=)) -> Index {
        var low = 0
        var high = self.count
        while low != high {
            let mid = (low + high) / 2
            if compare(self[mid][keyPath: keyPath], value) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
    mutating func insert<T:Comparable>(_ element: Element, orderedBy keyPath: KeyPath<Element, T>, compare: (T,T)->Bool = (<=)) {
        self.insert(element, at: findInsertPosition(element[keyPath: keyPath], orderedBy: keyPath, compare: compare))
    }
    func findOrderedPosition<T:Comparable>(_ v: T, orderedBy keyPath: KeyPath<Element, T>) -> Index {
        var low = 0
        var high = self.count
        
        while low != high {
            let mid = (low + high) / 2
            if self[mid][keyPath: keyPath] == v {
                return mid
            }
            if self[mid][keyPath: keyPath] < v {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return self.count
    }
    
}
extension Array where Element:BinaryInteger {
    public func findInsertPosition(_ value: Element, compare: (Element,Element)->Bool = (<=)) -> Index {
        var low = 0
        var high = self.count
        while low != high {
            let mid = (low + high) / 2
            if compare(self[mid], value) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
    public mutating func insert(_ element: Element, compare: (Element,Element)->Bool = (<=)) {
        self.insert(element, at: findInsertPosition(element, compare: compare))
    }
    public func findOrderedPosition(_ v: Element) -> Index {
        var low = 0
        var high = self.count
        
        while low != high {
            let mid = (low + high) / 2
            if self[mid] == v {
                return mid
            }
            if self[mid] < v {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return self.count
    }
}
