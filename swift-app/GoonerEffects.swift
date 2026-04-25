import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import CoreMedia

/// Handles all "Gooner-Modus" deep-fry distortion effects for video, photos, and audio.
enum GoonerEffects {
    
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // MARK: - Visual Deep-Fry (CIFilter Chain)
    
    /// Applies the full deep-fry filter chain to a CIImage.
    /// Used for both video frames and key photos.
    static func deepFry(_ input: CIImage) -> CIImage {
        var output = input
        
        // 1. Extreme color boost
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.saturation = 3.5
        colorControls.contrast = 3.0
        colorControls.brightness = 0.25
        output = colorControls.outputImage ?? output
        
        // 2. Pixellation
        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = output
        pixellate.scale = 6.0
        output = pixellate.outputImage ?? output
        
        // 3. Over-sharpening for crusty edges
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = output
        sharpen.radius = 3.0
        sharpen.intensity = 4.0
        output = sharpen.outputImage ?? output
        
        // 4. Radial bump distortion
        let bump = CIFilter.bumpDistortion()
        bump.inputImage = output
        bump.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
        bump.radius = Float(min(input.extent.width, input.extent.height)) * 0.4
        bump.scale = 0.35
        output = bump.outputImage ?? output
        
        return output.cropped(to: input.extent)
    }
    
    /// Renders a CIImage to CGImage.
    static func render(_ ciImage: CIImage) -> CGImage? {
        ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
    
    // MARK: - Key Photo Deep-Fry (with optional stretch)
    
    /// Applies deep-fry to a CGImage with optional aspect stretch distortion.
    static func deepFryCGImage(_ cgImage: CGImage, stretch: Bool = true) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let fried = deepFry(ciImage)
        
        guard let friedCG = render(fried) else { return nil }
        guard stretch else { return friedCG }
        
        // Stretch distortion: widen + squash
        let w = Int(Double(friedCG.width) * 1.4)
        let h = Int(Double(friedCG.height) * 0.75)
        
        guard let colorSpace = friedCG.colorSpace,
              let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: friedCG.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: friedCG.bitmapInfo.rawValue
              ) else { return friedCG }
        
        ctx.interpolationQuality = .low
        ctx.draw(friedCG, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
    
    // MARK: - Audio Distortion
    
    /// Applies overdrive + bit-crush distortion to an audio CMSampleBuffer.
    /// Modifies the data in the block buffer directly.
    /// Expects Int16 linear PCM mono input.
    static func distortAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        guard CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        ) == noErr, let ptr = dataPointer else { return }
        
        let count = length / MemoryLayout<Int16>.size
        
        ptr.withMemoryRebound(to: Int16.self, capacity: count) { samples in
            for i in 0..<count {
                var s = Float(samples[i])
                
                // Overdrive: 3x gain with hard clip
                s *= 3.0
                s = max(-32768, min(32767, s))
                
                // Bit crush: reduce to ~6-bit effective depth
                let crushFactor: Float = 512.0
                s = Float(Int(s / crushFactor)) * crushFactor
                
                samples[i] = Int16(clamping: Int(s))
            }
        }
    }
}
