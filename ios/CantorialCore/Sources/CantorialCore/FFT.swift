import Foundation

/// In-place radix-2 complex FFT with precomputed twiddle and bit-reversal tables.
/// Allocation-free after construction. Not thread-safe: use one instance per thread.
public final class FFT {
    public let size: Int
    private let cosTable: UnsafeMutablePointer<Float>
    private let sinTable: UnsafeMutablePointer<Float>
    private let bitReverse: UnsafeMutablePointer<Int>

    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0, "size must be a power of two")
        self.size = size
        cosTable = .allocate(capacity: size / 2)
        sinTable = .allocate(capacity: size / 2)
        bitReverse = .allocate(capacity: size)
        let levels = size.trailingZeroBitCount
        for i in 0..<(size / 2) {
            cosTable[i] = Float(cos(2.0 * Double.pi * Double(i) / Double(size)))
            sinTable[i] = Float(sin(2.0 * Double.pi * Double(i) / Double(size)))
        }
        for i in 0..<size {
            var r = 0
            var x = i
            for _ in 0..<levels {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            bitReverse[i] = r
        }
    }

    deinit {
        cosTable.deallocate()
        sinTable.deallocate()
        bitReverse.deallocate()
    }

    /// Forward DFT: X[k] = sum x[n] * e^(-2*pi*i*k*n/N), on `size` values of `re` and `im`.
    public func forward(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>) {
        let n = size
        for i in 0..<n {
            let j = bitReverse[i]
            if j > i {
                let tr = re[i]; re[i] = re[j]; re[j] = tr
                let ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var half = 1
        while half < n {
            let step = n / (half * 2)
            var start = 0
            while start < n {
                var k = 0
                for j in start..<(start + half) {
                    let c = cosTable[k]
                    let s = sinTable[k]
                    let l = j + half
                    let tre = re[l] * c + im[l] * s
                    let tim = im[l] * c - re[l] * s
                    re[l] = re[j] - tre
                    im[l] = im[j] - tim
                    re[j] += tre
                    im[j] += tim
                    k += step
                }
                start += half * 2
            }
            half *= 2
        }
    }
}
