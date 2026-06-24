import SwiftUI

struct QuantityStepper: View {
    @Binding var quantity: Int
    let range: ClosedRange<Int>

    init(quantity: Binding<Int>, range: ClosedRange<Int> = 1...99) {
        self._quantity = quantity
        self.range = range
    }

    var body: some View {
        Stepper("Quantità: \(quantity)", value: $quantity, in: range)
    }
}
