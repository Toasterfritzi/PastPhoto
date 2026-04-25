import SwiftUI

/// A custom slider built entirely with Apple's Liquid Glass design.
/// Uses `.glassEffect()` on the track and thumb for a native iOS 26 look.
struct GlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    var icon: String
    var unit: String
    var tintColor: Color = .accentColor
    var decimals: Int = 1
    
    @State private var isDragging = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label + current value
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tintColor)
                    .font(.subheadline)
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(formattedValue)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.clear, in: .capsule)
            }
            
            // Custom Glass Track + Thumb
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let thumbSize: CGFloat = isDragging ? 32 : 26
                let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let clampedProgress = min(max(progress, 0), 1)
                let thumbX = clampedProgress * (trackWidth - thumbSize)
                
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .frame(height: 6)
                        .glassEffect(.clear, in: .capsule)
                    
                    // Filled track
                    Capsule()
                        .fill(tintColor.opacity(0.4))
                        .frame(width: CGFloat(clampedProgress) * trackWidth, height: 6)
                    
                    // Glass thumb
                    Circle()
                        .frame(width: thumbSize, height: thumbSize)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .shadow(color: tintColor.opacity(0.3), radius: isDragging ? 8 : 0)
                        .offset(x: thumbX)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    isDragging = true
                                    let fraction = gesture.location.x / trackWidth
                                    let clamped = min(max(fraction, 0), 1)
                                    value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(duration: 0.3)) {
                                        isDragging = false
                                    }
                                }
                        )
                }
                .frame(height: 32)
            }
            .frame(height: 32)
        }
    }
    
    private var formattedValue: String {
        "\(String(format: "%.\(decimals)f", value))\(unit)"
    }
}
