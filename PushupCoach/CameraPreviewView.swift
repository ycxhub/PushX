import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var showSafeFrameGuide: Bool = true
    var onPreviewLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    final class Coordinator {
        var onPreviewLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.showSafeFrameGuide = showSafeFrameGuide
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onLayerReady = { [weak coordinator = context.coordinator] layer in
            coordinator?.onPreviewLayerReady?(layer)
        }
        context.coordinator.onPreviewLayerReady = onPreviewLayerReady
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.onPreviewLayerReady = onPreviewLayerReady
        uiView.showSafeFrameGuide = showSafeFrameGuide
        uiView.onLayerReady = { [weak coordinator = context.coordinator] layer in
            coordinator?.onPreviewLayerReady?(layer)
        }
        uiView.previewLayer.session = session
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }

    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    /// Coaching box drawn in the same coordinate space as the preview (fixes off-screen SwiftUI overlay).
    var showSafeFrameGuide: Bool = true {
        didSet { setNeedsLayout() }
    }

    private let safeFrameLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInitSafeFrame()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInitSafeFrame()
    }

    private func commonInitSafeFrame() {
        safeFrameLayer.fillColor = UIColor.white.withAlphaComponent(0.1).cgColor
        safeFrameLayer.strokeColor = UIColor.white.withAlphaComponent(0.88).cgColor
        safeFrameLayer.lineWidth = 4
        safeFrameLayer.lineJoin = .round
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        CapturePortraitConfiguration.applyPortraitMirroredFrontCamera(to: previewLayer.connection)

        if showSafeFrameGuide {
            if safeFrameLayer.superlayer == nil {
                previewLayer.addSublayer(safeFrameLayer)
            }
            safeFrameLayer.frame = previewLayer.bounds
            safeFrameLayer.isHidden = false
            updateSafeFramePath()
        } else {
            safeFrameLayer.isHidden = true
            safeFrameLayer.path = nil
        }

        onLayerReady?(previewLayer)
    }

    private func updateSafeFramePath() {
        let inset = PushupPoseConstants.safeFrameInset
        let tiny: CGFloat = 0.001
        let metaRect = CGRect(
            x: max(0, inset),
            y: max(0, inset),
            width: max(tiny, 1 - 2 * inset),
            height: max(tiny, 1 - 2 * inset)
        )
        // `layerRectConverted(fromMetadataOutputRect:)` is in the preview layer’s coordinate system.
        let localRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metaRect)
        safeFrameLayer.path = UIBezierPath(roundedRect: localRect, cornerRadius: 16).cgPath
    }
}
