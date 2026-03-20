import AVFoundation

/// Keeps **preview** and **video data output** in the same portrait + mirror setup.
/// If they diverge, landmarks look rotated (e.g. dots “horizontal” vs vertical video).
enum CapturePortraitConfiguration {

    /// Portrait upright, mirrored for front camera — use on both `AVCaptureVideoDataOutput` and `AVCaptureVideoPreviewLayer` connections.
    static func applyPortraitMirroredFrontCamera(to connection: AVCaptureConnection?) {
        guard let connection else { return }

        // iOS 17+: use rotation angle only. `videoOrientation` / `isVideoOrientationSupported`
        // are deprecated and may fail Swift 6 / latest SDK builds.
        let portraitAngle: CGFloat = 90
        if connection.isVideoRotationAngleSupported(portraitAngle) {
            connection.videoRotationAngle = portraitAngle
        }

        if connection.isVideoMirroringSupported {
            // Manual mirroring requires turning off automatic adjustment or `isVideoMirrored` throws.
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}
