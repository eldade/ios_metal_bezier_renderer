//    Copyright (c) 2016, Eldad Eilam
//    All rights reserved.
//
//    Redistribution and use in source and binary forms, with or without modification, are
//    permitted provided that the following conditions are met:
//
//    1. Redistributions of source code must retain the above copyright notice, this list of
//       conditions and the following disclaimer.
//
//    2. Redistributions in binary form must reproduce the above copyright notice, this list
//       of conditions and the following disclaimer in the documentation and/or other materials
//       provided with the distribution.
//
//    3. Neither the name of the copyright holder nor the names of its contributors may be used
//       to endorse or promote products derived from this software without specific prior written
//       permission.
//
//    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
//    OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
//    AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
//    CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//    WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import CoreFoundation
import Metal

class PageAlignedArrayImpl<T> {
    var space: Int
    var ptr: UnsafeMutablePointer<T>
    
    static private func alignedAlloc(count: Int) -> UnsafeMutablePointer<T> {
        var newAddr:UnsafeMutableRawPointer?
        let alignment : Int = Int(getpagesize())
        var size : Int
        
        if count == 0 {
            size = MemoryLayout<T>.size / Int(getpagesize())
            
            if MemoryLayout<T>.size % Int(getpagesize()) != 0 {
                size += Int(getpagesize())
            }
        } else {
            size = Int(count * MemoryLayout<T>.size)
        }
        
        posix_memalign(&newAddr, alignment, size)
        
        return newAddr!.assumingMemoryBound(to: T.self)
    }
    
    static private func freeAlignedAlloc(addr : UnsafeMutablePointer<T>) {
        free(addr)
    }

    
    init(count: Int = 0, ptr: UnsafeMutablePointer<T>? = nil) {
        self.count = count
        self.space = Int(getpagesize()) / MemoryLayout<T>.size
        
        self.ptr = PageAlignedArrayImpl.alignedAlloc(count: count)
        
        if ptr != nil {
            self.ptr.initialize(from: ptr!, count: count)
        }
    }
    
    var count : Int {
        didSet {
            if space <= count {
                let newSpace = count * 2
                let newPtr = PageAlignedArrayImpl.alignedAlloc(count: newSpace)
                
                newPtr.moveInitialize(from: ptr, count: oldValue)
                
                PageAlignedArrayImpl.freeAlignedAlloc(addr: ptr)
                ptr = newPtr
                space = newSpace
            }
        }
    }
    
    func copy() -> PageAlignedArrayImpl<T> {
        return PageAlignedArrayImpl<T>(count: count, ptr: ptr)
    }
    
    deinit {
        ptr.deinitialize(count: count)
        PageAlignedArrayImpl.freeAlignedAlloc(addr: ptr)
    }
}

struct PageAlignedContiguousArray<T>: RangeReplaceableCollection {
    private var impl: PageAlignedArrayImpl<T> = PageAlignedArrayImpl<T>(count: 0)

    /// Replaces the specified subrange of elements with the given collection.
    ///
    /// This method has the effect of removing the specified range of elements
    /// from the collection and inserting the new elements at the same location.
    /// The number of new elements need not match the number of elements being
    /// removed.
    ///
    /// In this example, three elements in the middle of an array of integers are
    /// replaced by the five elements of a `Repeated<Int>` instance.
    ///
    ///      var nums = [10, 20, 30, 40, 50]
    ///      nums.replaceSubrange(1...3, with: repeatElement(1, count: 5))
    ///      print(nums)
    ///      // Prints "[10, 1, 1, 1, 1, 1, 50]"
    ///
    /// If you pass a zero-length range as the `subrange` parameter, this method
    /// inserts the elements of `newElements` at `subrange.startIndex`. Calling
    /// the `insert(contentsOf:at:)` method instead is preferred.
    ///
    /// Likewise, if you pass a zero-length collection as the `newElements`
    /// parameter, this method removes the elements in the given subrange
    /// without replacement. Calling the `removeSubrange(_:)` method instead is
    /// preferred.
    ///
    /// Calling this method may invalidate any existing indices for use with this
    /// collection.
    ///
    /// - Parameters:
    ///   - subrange: The subrange of the collection to replace. The bounds of
    ///     the range must be valid indices of the collection.
    ///   - newElements: The new elements to add to the collection.
    ///
    /// - Complexity: O(*m*), where *m* is the combined length of the collection
    ///   and `newElements`. If the call to `replaceSubrange` simply appends the
    ///   contents of `newElements` to the collection, the complexity is O(*n*),
    ///   where *n* is the length of `newElements`.
    public mutating func replaceSubrange<C>(_ subrange: Range<Int>, with newElements: C) where C : Collection, C.Iterator.Element == T {
        let newCount = newElements.count as! Int
        let oldCount = self.count
        let eraseCount = subrange.count
        
        let growth = newCount - eraseCount
        impl.count = oldCount + growth
        
        let elements = impl.ptr
        let oldTailIndex = subrange.upperBound
        let oldTailStart = elements + oldTailIndex
        let newTailIndex = oldTailIndex + growth
        let newTailStart = oldTailStart + growth
        let tailCount = oldCount - subrange.upperBound
        
        if growth > 0 {
            // Slide the tail part of the buffer forwards, in reverse order
            // so as not to self-clobber.
            newTailStart.moveInitialize(from: oldTailStart, count: tailCount)
            
            // Assign over the original subRange
            var i = newElements.startIndex
            for j in CountableRange(subrange) {
                elements[j] = newElements[i]
                newElements.formIndex(after: &i)
            }
            // Initialize the hole left by sliding the tail forward
            for j in oldTailIndex..<newTailIndex {
                (elements + j).initialize(to: newElements[i])
                newElements.formIndex(after: &i)
            }
        }
        else { // We're not growing the buffer
            // Assign all the new elements into the start of the subRange
            var i = subrange.lowerBound
            var j = newElements.startIndex
            for _ in 0..<newCount {
                elements[i] = newElements[j]
                formIndex(after: &i)
                newElements.formIndex(after: &j)
            }
            
            // If the size didn't change, we're done.
            if growth == 0 {
                return
            }
            
            // Move the tail backward to cover the shrinkage.
            let shrinkage = -growth
            if tailCount > shrinkage {   // If the tail length exceeds the shrinkage
                
                // Assign over the rest of the replaced range with the first
                // part of the tail.
                newTailStart.moveAssign(from: oldTailStart, count: shrinkage)
                
                // Slide the rest of the tail back
                oldTailStart.moveInitialize(
                    from: oldTailStart + shrinkage, count: tailCount - shrinkage)
            }
            else {                      // Tail fits within erased elements
                // Assign over the start of the replaced range with the tail
                newTailStart.moveAssign(from: oldTailStart, count: tailCount)
                
                // Destroy elements remaining after the tail in subRange
                (newTailStart + tailCount).deinitialize(
                    count: shrinkage - tailCount)
            }
        }
    }

    /// Returns the position immediately after the given index.
    ///
    /// - Parameter i: A valid index of the collection. `i` must be less than
    ///   `endIndex`.
    /// - Returns: The index value immediately after `i`.
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    var buffer : UnsafeMutablePointer<T> {
        return impl.ptr
    }
    
    var bufferLength : Int {
        return impl.space * MemoryLayout<T>.size
    }
    
   
    var count: Int {
        return impl.count
    }
    
    subscript(index: Int) -> T {
        get {
            assert (index < count, "Array index out of range")
            return impl.ptr[index]
        }
        mutating set {
            assert (index < count, "Array index out of range")
            impl.ptr[index] = newValue
        }
    }
    
    var description: String {
        return String(format: "Aligned buffer: %x", impl.ptr)
    }
    
    typealias Index = Int
    
    var startIndex: Index {
        return 0
    }
    
    var endIndex: Index {
        return count
    }
    
    typealias Generator = AnyIterator<T>
    
    func generate() -> Generator {
        var index = 0
        return AnyIterator<T> {
            if index < self.count {
                index += 1
                return self[index]
            } else {
                return nil
            }
        }
    }
}

extension PageAlignedContiguousArray : ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: T...) {
        self.init()
        for element in elements {
            append(element)
        }
    }
}

extension MTLDevice {
    func makeBufferWithPageAlignedArray<T>(_ array: PageAlignedContiguousArray<T>) -> MTLBuffer? {
        return self.makeBuffer(bytesNoCopy: array.buffer, length: array.bufferLength, options: .storageModeShared, deallocator: nil)
    }
}
