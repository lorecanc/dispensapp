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
            .accessibilityLabel("Quantità")
            .accessibilityValue("\(quantity)")
            .accessibilityHint("Usa più e meno per regolare la quantità tra \(range.lowerBound) e \(range.upperBound)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if quantity < range.upperBound { quantity += 1 }
                case .decrement:
                    if quantity > range.lowerBound { quantity -= 1 }
                @unknown default:
                    break
                }
            }
            .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
