
import Foundation
import AVFoundation
import Combine
import CoreVideo

// MARK: - Camera Errors

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

// MARK: - Thread-Safe Sensitivity

private final class SensitivityStore: @unchecked Sendable {

    private let lock = NSLock()
    private var storedValue: Double = 0.30

    func set(_ value: Double) {
        let clamped = min(max(value, 0.10), 0.60)

        lock.lock()
        storedValue = clamped
        lock.unlock()
    }

    func get() -> Double {
        lock.lock()
        defer { lock.unlock() }

        return storedValue
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

    private let sensitivity: SensitivityStore
    private let onState: @Sendable (GazeState) -> Void

    init(
        sensitivity: SensitivityStore,
        onState: @escaping @Sendable (GazeState) -> Void
    ) {
        self.sensitivity = sensitivity
        self.onState = onState
    }

    // MARK: - Reset

    func reset() {
        lock.lock()
        receivedFrame = false
        lock.unlock()

        // Reset detection state on the frame queue
        // before the next camera session starts.
        lastAnalysis = .distantPast
        lastState = nil
    }

    // MARK: - Frame Status

    func hasReceivedFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return receivedFrame
    }

    // MARK: - Camera Frame Processing

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

        // Read the latest slider value safely.
        let threshold = sensitivity.get()

        // The detector is modified only on this queue.
        detector.setYawThreshold(threshold)

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

    init(
        sensitivity: SensitivityStore,
        onState: @escaping @Sendable (GazeState) -> Void
    ) {
        receiver = FrameReceiver(
            sensitivity: sensitivity,
            onState: onState
        )
    }

    // MARK: - Start

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

    // MARK: - Stop

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Frame Status

    func hasReceivedFrame() -> Bool {
        receiver.hasReceivedFrame()
    }

    // MARK: - Configure Camera

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

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var status = "Camera stopped"
    @Published private(set) var gazeState = GazeState.unknown

    // MARK: - Sensitivity

    private let sensitivity = SensitivityStore()

    func setYawThreshold(_ value: Double) {
        sensitivity.set(value)

        print(
            "Shroud: Head-turn threshold set to \(value)"
        )
    }

    // MARK: - Camera Session

    private lazy var cameraSession = CameraSessionActor(
        sensitivity: sensitivity
    ) { [weak self] state in

        Task { @MainActor [weak self] in
            guard let self, self.isRunning else {
                return
            }

            self.gazeState = state
        }
    }

    // MARK: - Operation State

    private var operationTask: Task<Void, Never>?
    private var generation = 0
    private var wantsRunning = false

    // MARK: - Start Camera

    func start() {

        guard !wantsRunning else {
            return
        }

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
                  wantsRunning else {
                return
            }

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

    // MARK: - Stop Camera

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
