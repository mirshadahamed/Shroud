
import Foundation
import AVFoundation
import Combine
import CoreVideo

private enum CameraError: LocalizedError {
    case cameraNotFound
    case cannotAddInput
    case cannotAddOutput
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .cameraNotFound:
            return "Built-in camera not found"
        case .cannotAddInput:
            return "Cannot add camera input"
        case .cannotAddOutput:
            return "Cannot add video output"
        case .failedToStart:
            return "Camera failed to start"
        }
    }
}

// MARK: - Video Frame Receiver

private final class FrameReceiver:
    NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {

    private let lock = NSLock()
    private var receivedFrame = false

    // Accessed only on the serial video frame queue.
    private let detector = GazeDetector()
    private var lastAnalysis = Date.distantPast
    private var lastState: GazeState?

    private let onState: @Sendable (GazeState) -> Void

    init(onState: @escaping @Sendable (GazeState) -> Void) {
        self.onState = onState
    }

    func reset() {
        lock.lock()
        receivedFrame = false
        lock.unlock()
    }

    func hasReceivedFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedFrame
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        receivedFrame = true
        lock.unlock()

        let now = Date()

        guard now.timeIntervalSince(lastAnalysis) >= 0.2 else {
            return
        }

        lastAnalysis = now

        guard let buffer =
            CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let state = detector.analyze(buffer)

        if state != lastState {
            lastState = state
            onState(state)
        }
    }
}

// MARK: - Camera Session

private actor CameraSessionActor {

    private let session = AVCaptureSession()
    private let receiver: FrameReceiver

    private let frameQueue = DispatchQueue(
        label: "com.shroud.camera.frames"
    )

    private var isConfigured = false

    init(onState: @escaping @Sendable (GazeState) -> Void) {
        receiver = FrameReceiver(onState: onState)
    }

    func start() throws {
        if !isConfigured {
            try configure()
        }

        receiver.reset()

        if !session.isRunning {
            session.startRunning()
        }

        guard session.isRunning else {
            throw CameraError.failedToStart
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func hasReceivedFrame() -> Bool {
        receiver.hasReceivedFrame()
    }

    private func configure() throws {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )

        guard let camera = discovery.devices.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains(
                "FaceTime"
            )
        }) ?? discovery.devices.first else {
            throw CameraError.cameraNotFound
        }

        let input = try AVCaptureDeviceInput(
            device: camera
        )

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .low

        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ]

        output.setSampleBufferDelegate(
            receiver,
            queue: frameQueue
        )

        guard session.canAddOutput(output) else {
            throw CameraError.cannotAddOutput
        }

        session.addOutput(output)
        isConfigured = true
    }
}

// MARK: - Observable Camera Manager

@MainActor
final class CameraManager: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var status = "Camera stopped"
    @Published private(set) var gazeState = GazeState.unknown

    private lazy var cameraSession = CameraSessionActor {
        [weak self] state in

        Task { @MainActor [weak self] in
            guard let self, self.isRunning else {
                return
            }

            self.gazeState = state
        }
    }

    private var operationTask: Task<Void, Never>?
    private var generation = 0
    private var wantsRunning = false

    func start() {
        guard !wantsRunning else { return }

        wantsRunning = true
        generation += 1
        let currentGeneration = generation

        gazeState = .unknown
        status = "Requesting camera permission..."

        operationTask?.cancel()

        operationTask = Task {
            let granted = await AVCaptureDevice
                .requestAccess(for: .video)

            guard currentGeneration == generation,
                  wantsRunning else { return }

            guard granted else {
                wantsRunning = false
                status = "Camera permission denied"
                return
            }

            status = "Starting camera..."

            do {
                try await cameraSession.start()

                guard currentGeneration == generation,
                      wantsRunning else {
                    await cameraSession.stop()
                    return
                }

                var received = false

                for _ in 0..<20 {
                    if await cameraSession.hasReceivedFrame() {
                        received = true
                        break
                    }

                    try? await Task.sleep(
                        for: .milliseconds(100)
                    )

                    if currentGeneration != generation {
                        return
                    }
                }

                guard currentGeneration == generation,
                      wantsRunning else {
                    await cameraSession.stop()
                    return
                }

                if received {
                    isRunning = true
                    status = "Camera active"
                } else {
                    await cameraSession.stop()
                    wantsRunning = false
                    isRunning = false
                    status = "No camera frames received"
                }

            } catch {
                guard currentGeneration == generation else {
                    return
                }

                wantsRunning = false
                isRunning = false
                status = error.localizedDescription
            }
        }
    }

    func stop() {
        wantsRunning = false
        generation += 1
        let currentGeneration = generation

        operationTask?.cancel()

        isRunning = false
        gazeState = .unknown
        status = "Stopping camera..."

        operationTask = Task {
            await cameraSession.stop()

            guard currentGeneration == generation else {
                return
            }

            status = "Camera stopped"
        }
    }
}
