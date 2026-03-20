import AVFoundation
import CoreGraphics
import ImageIO
import UIKit

/// Maps camera sample-buffer pixel layout to orientation APIs used by Vision and MediaPipe Tasks.
///
/// **Portrait-only app** (see `Info.plist`): the capture pipeline applies a 90° rotation and mirror on
/// both `AVCaptureVideoDataOutput` and `AVCaptureVideoPreviewLayer` via ``CapturePortraitConfiguration``.
/// Vision and MediaPipe must use the **same** `CGImagePropertyOrientation` as the pixel buffer would appear
/// when upright on screen, or inference sees a sideways image (MediaPipe often returns empty results;
/// Vision landmarks drift from the preview).
///
/// **Front camera:** we use `.leftMirrored` to match common Apple sample code for portrait + mirrored preview.
/// If preview and data-output connections ever diverge, fix that first—do not patch landmark math.
///
/// **MediaPipe:** normalized `(x, y)` from BlazePose are mapped with ``mediaPipeNormalizedToMetadataNormalized``
/// so they land in the same top-left metadata `[0,1]²` space that
/// `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)` expects for overlay dots.
enum VisionOrientation {

    /// Orientation of pixel data inside `CMSampleBuffer` for `VNImageRequestHandler`.
    static func cgImageOrientation(from connection: AVCaptureConnection, devicePosition: AVCaptureDevice.Position) -> CGImagePropertyOrientation {
        cgImagePropertyOrientation(devicePosition: devicePosition)
    }

    /// Same geometry as ``cgImageOrientation`` for `MPImage(sampleBuffer:orientation:)`.
    static func uiImageOrientation(from connection: AVCaptureConnection, devicePosition: AVCaptureDevice.Position) -> UIImage.Orientation {
        cgImageOrientation(from: connection, devicePosition: devicePosition).uiImageOrientation
    }

    /// Maps MediaPipe normalized landmark `(x, y)` into the same `[0,1]²` metadata space that
    /// `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)` expects for our
    /// portrait front-camera pipeline. Without this, overlays track ~90° wrong (e.g. head left → dots move up).
    static func mediaPipeNormalizedToMetadataNormalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.y, y: p.x)
    }

    /// Portrait-only app (see Info.plist). Matches common Apple camera / Vision sample mappings.
    private static func cgImagePropertyOrientation(devicePosition: AVCaptureDevice.Position) -> CGImagePropertyOrientation {
        switch devicePosition {
        case .front:
            return .leftMirrored
        case .back:
            return .right
        case .unspecified:
            return .up
        @unknown default:
            return .up
        }
    }
}

extension CGImagePropertyOrientation {
    var uiImageOrientation: UIImage.Orientation {
        switch self {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }
}

extension AVCaptureVideoPreviewLayer {
    func layerPoint(fromMetadataNormalizedTopLeft point: CGPoint) -> CGPoint {
        let tiny: CGFloat = 0.002
        let meta = CGRect(
            x: max(0, min(1 - tiny, point.x)),
            y: max(0, min(1 - tiny, point.y)),
            width: tiny,
            height: tiny
        )
        let converted = layerRectConverted(fromMetadataOutputRect: meta)
        return CGPoint(x: converted.midX, y: converted.midY)
    }
}
