
import Foundation
import Vision
import CoreVideo
import ImageIO

// MARK: - Gaze States

enum GazeState: String, Sendable {
    case facingScreen = "Facing screen"
    case lookingAway = "Head turned away"
    case noFace = "Face not detected"
    case unknown = "Direction unavailable"
}

// MARK: - Gaze Detector

final class GazeDetector {

    private let request = VNDetectFaceRectanglesRequest()

    // Only accessed from the serial camera frame queue.
    private var yawThreshold: Double = 0.30

    // MARK: - Sensitivity

    func setYawThreshold(_ value: Double) {
        yawThreshold = min(max(value, 0.10), 0.60)
    }

    // MARK: - Analyze Camera Frame

    func analyze(_ pixelBuffer: CVPixelBuffer) -> GazeState {

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])

            guard let face = request.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height
                    <
                $1.boundingBox.width * $1.boundingBox.height
            }) else {
                return .noFace
            }

            guard let yaw = face.yaw?.doubleValue else {
                return .unknown
            }

            return abs(yaw) > yawThreshold
                ? .lookingAway
                : .facingScreen

        } catch {
            return .unknown
        }
    }
}
