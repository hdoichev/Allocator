//
//  File.swift
//  
//
//  Created by Hristo Doichev on 10/7/21.
//

import Foundation

///
extension Allocator.Chunks {
    func print(_ header: String) {
        Swift.print(header)
        forEach { Swift.print("Address: ", $0.address, ", Count: ", $0.count) }
    }
}
extension Allocator.Chunks {
    public mutating func deallocate(_ allocator: Allocator) {
        allocator.deallocate(chunks: self)
        self.removeAll()
    }
}
///
extension ContiguousArray {
    func findInsertPosition<T:Comparable>(_ value: T, orderedBy keyPath: KeyPath<Element, T>, compare: (T,T)->Bool = (<=)) -> Index {
        var low = 0
        var high = self.count
        self.withUnsafeBufferPointer { buffer in
            while low != high {
                let mid = (low + high) / 2
                if compare(buffer[mid][keyPath: keyPath], value) {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
        }
        return low
    }
    func findInsertPosition_old<T:Comparable>(_ value: T, orderedBy keyPath: KeyPath<Element, T>, compare: (T,T)->Bool = (<=)) -> Index {
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
///
extension ContiguousArray where Element:BinaryInteger {
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
///
extension ContiguousArray where Element == Int {
    func sunOfLowerElements() -> ContiguousArray<Int> {
        var res = ContiguousArray<Int>()
        var sum: Int = 0
        self.forEach { e in
            res.append(sum)
            sum = sum + e
        }
        return res
    }
}
///
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
///
extension Int {
    @inlinable
    public func decrementedClampToZero(_ by:Int) -> Int {
        guard self > by else { return 0 }
        return self - by
    }
}
