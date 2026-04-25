import SwiftUI

/// A custom segmented picker built entirely with Apple's Liquid Glass design.
/// The selected segment uses `.glassEffect(.regular.interactive())` and morphs
/// fluidly between segments via `glassEffectID` within a `GlassEffectContainer`.
struct GlassSegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String
    var icon: String? = nil
    
    @Namespace private var pickerNamespace
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Optional section label
            if let icon = icon {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(label(selection))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Segmented picker with glass morphing
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = selection == option
                        
                        Text(label(option))
                            .font(.subheadline.weight(isSelected ? .bold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .glassEffect(
                                isSelected ? .regular.interactive() : .clear,
                                in: .capsule
                            )
                            .glassEffectID(option, in: pickerNamespace)
                            .contentShape(.rect)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                                    selection = option
                                }
                            }
                    }
                }
            }
            .padding(4)
            .glassEffect(.clear, in: .capsule)
        }
    }
}
