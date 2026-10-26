
import Foundation
import Vision
import CoreVideo
import ImageIO

enum GazeState: String, Sendable {
    case facingScreen = "Facing screen"
    case lookingAway = "Head turned away"
    case noFace = "Face not detected"
    case unknown = "Direction unavailable"
}

final class GazeDetector {
    private let request = VNDetectFaceRectanglesRequest()

    // Approximately 17 degrees
    var yawThreshold: Double = 0.30

    func analyze(_ pixelBuffer: CVPixelBuffer) -> GazeState {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])

            guard let face = request.results?.max(by: {
                $0.boundingBox.width * $0.boundingBox.height <
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
