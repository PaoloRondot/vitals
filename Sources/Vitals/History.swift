import Foundation

/// Fixed-capacity sample history for sparklines (~6 min at a 2 s interval).
struct History {
    private(set) var values: [Double] = []
    let capacity: Int

    init(capacity: Int = 180) {
        self.capacity = capacity
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}
