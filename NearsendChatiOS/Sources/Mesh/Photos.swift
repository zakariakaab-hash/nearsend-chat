import UIKit

/// Makes a picture as small as Bluetooth likes it: resized and re-encoded as JPEG of at most about 14 KB (about 20 chunks). Re-encoding drops the
/// camera metadata (the GPS position included). Android receivers decode JPEG as well as WebP (PROTOCOL.md section 11).
enum Photos {
    static let maxBytes = 14_000
    private static let sizes: [CGFloat] = [640, 560, 480, 400, 340, 280, 220]
    private static let qualities: [CGFloat] = [0.42, 0.32, 0.24, 0.16]

    static func compress(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        var best: Data?
        for size in sizes {
            let scale = min(1, size / max(image.size.width, image.size.height))
            let target = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1; format.opaque = true
            let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
            for q in qualities {
                guard let jpeg = scaled.jpegData(compressionQuality: q) else { continue }
                best = jpeg
                if jpeg.count <= maxBytes { return jpeg }
            }
        }
        if let best, best.count <= 20_000 { return best }
        return nil
    }
}
