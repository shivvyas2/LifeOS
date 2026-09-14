import SwiftUI
import CoreImage
import DesignSystem

/// The photograph supplies the gradient; it is recomputed only when the photo changes.
struct ProfilePhotoBackdrop: View {
    let photo: Data?
    var showsPortrait = true
    @State private var palette = ProfilePhotoPalette.fallback

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(colors: [palette.top, palette.middle, palette.bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 70).opacity(0.35)
                        .clipped()
                    if showsPortrait {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.width * 1.3, alignment: .top)
                            .clipped()
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                                         .init(color: .black, location: 0.58),
                                                         .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                } else {
                    Ellipse().fill(LifeOSTokens.accent.opacity(0.26))
                        .frame(width: proxy.size.width, height: 360).blur(radius: 90)
                        .offset(x: proxy.size.width * 0.2, y: 20)
                }
                LinearGradient(stops: [.init(color: .black.opacity(0.12), location: 0),
                                       .init(color: .black.opacity(0.18), location: 0.3),
                                       .init(color: .black.opacity(0.55), location: 0.65),
                                       .init(color: .black.opacity(0.65), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: photo) { palette = ProfilePhotoPalette.extract(from: photo) }
        .accessibilityHidden(true)
    }
}

private struct ProfilePhotoPalette {
    let top: Color
    let middle: Color
    let bottom: Color

    static let fallback = Self(top: Color(red: 0.36, green: 0.25, blue: 0.21),
                               middle: Color(red: 0.26, green: 0.25, blue: 0.29),
                               bottom: Color(red: 0.15, green: 0.20, blue: 0.25))
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func extract(from data: Data?) -> Self {
        guard let data, let image = UIImage(data: data) else { return fallback }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format)
            .image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 48, height: 48)) }
        guard let source = CIImage(image: thumbnail) else { return fallback }
        func average(_ y: CGFloat) -> Color {
            let bounds = CGRect(x: 0, y: y, width: 48, height: 16)
            let result = source.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: bounds)])
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(result, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
            return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255,
                         blue: Double(pixel[2]) / 255)
        }
        return Self(top: average(32), middle: average(16), bottom: average(0))
    }
}
