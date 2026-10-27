
import Foundation
import AppKit
import AVFoundation
import Combine
import CoreVideo

// MARK: - Camera Errors

private enum ShroudCameraError: LocalizedError {
    case cameraNotFound
    case cannotAddInput
    case cannotAddOutput
    case failedToStart
    case noFrames

    var errorDescription: String? {
        switch self {
        case .cameraNotFound:
            return "Built-in camera not found"
        case .cannotAddInput:
            return "Cannot configure camera input"
        case .cannotAddOutput:
            return "Cannot configure camera output"
        case .failedToStart:
            return "Camera failed to start"
        case .noFrames:
            return "Camera is not delivering frames"
        }
    }
}

// MARK: - Thread-Safe Sensitivity

private final class SensitivityStore: @unchecked Sendable {

    private let lock = NSLock()
    private var storedValue: Double = 0.30

    func set(_ value: Double) {
        lock.lock()
        storedValue = min(max(value, 0.10), 0.60)
        lock.unlock()
    }

    func get() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

// MARK: - Thread-Safe Frame Activity

private final class FrameActivity: @unchecked Sendable {

    private let lock = NSLock()
    private var lastFrame: Date?

    func reset() {
        lock.lock()
        lastFrame = nil
        lock.unlock()
    }

    func recordFrame() {
        lock.lock()
        lastFrame = Date()
        lock.unlock()
    }

    func hasReceivedFrame() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lastFrame != nil
    }

    func secondsSinceLastFrame() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }

        guard let lastFrame else {
            return nil
        }

        return Date().timeIntervalSince(lastFrame)
    }
}

// MARK: - Camera Frame Receiver

private final class FrameReceiver:
    NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {

    private let detector = GazeDetector()
    private let sensitivity: SensitivityStore
    private let activity: FrameActivity

    private let onState: @Sendable (GazeState) -> Void

    // Access these only on the serial frame queue.
    private var lastAnalysis = Date.distantPast
    private var lastState: GazeState?

    init(
        sensitivity: SensitivityStore,
        activity: FrameActivity,
        onState: @escaping @Sendable (GazeState) -> Void
    ) {
        self.sensitivity = sensitivity
        self.activity = activity
        self.onState = onState

        super.init()
    }

    // Must be called on the frame queue.
    func resetForNewSession() {
        lastAnalysis = .distantPast
        lastState = nil
        activity.reset()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        activity.recordFrame()

        let now = Date()

        // Analyze at approximately five frames per second.
        guard now.timeIntervalSince(lastAnalysis) >= 0.20 else {
            return
        }

        lastAnalysis = now

        guard let pixelBuffer =
            CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        detector.setYawThreshold(
            sensitivity.get()
        )

        let state = detector.analyze(pixelBuffer)

        // Send the first result after every restart.
        guard state != lastState else {
            return
        }

        lastState = state
        onState(state)
    }
}

// MARK: - Camera Session Actor

private actor CameraSessionActor {

    private let session = AVCaptureSession()

    private let frameQueue = DispatchQueue(
        label: "com.shroud.camera.frames"
    )

    private let activity = FrameActivity()
    private let receiver: FrameReceiver

    private var isConfigured = false

    init(
        sensitivity: SensitivityStore,
        onState: @escaping @Sendable (GazeState) -> Void
    ) {
        receiver = FrameReceiver(
            sensitivity: sensitivity,
            activity: activity,
            onState: onState
        )
    }

    func start() throws {

        if !isConfigured {
            try configure()
        }

        if session.isRunning {
            session.stopRunning()
        }

        // The receiver's analysis state belongs to frameQueue.
        // Resetting it there avoids a race with callbacks.
        frameQueue.sync {
            receiver.resetForNewSession()
        }

        session.startRunning()

        guard session.isRunning else {
            throw ShroudCameraError.failedToStart
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }

        frameQueue.sync {
            receiver.resetForNewSession()
        }
    }

    func hasReceivedFrame() -> Bool {
        activity.hasReceivedFrame()
    }

    func secondsSinceLastFrame() -> TimeInterval? {
        activity.secondsSinceLastFrame()
    }

    // MARK: - Session Configuration

    private func configure() throws {

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        let devices = discovery.devices

        guard let camera = devices.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains(
                "FaceTime"
            )
        }) ?? devices.first else {
            throw ShroudCameraError.cameraNotFound
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .low

        let input = try AVCaptureDeviceInput(
            device: camera
        )

        guard session.canAddInput(input) else {
            throw ShroudCameraError.cannotAddInput
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()

        output.alwaysDiscardsLateVideoFrames = true

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA)
        ]

        guard session.canAddOutput(output) else {
            throw ShroudCameraError.cannotAddOutput
        }

        session.addOutput(output)

        output.setSampleBufferDelegate(
            receiver,
            queue: frameQueue
        )

        isConfigured = true
    }

    // MARK: - Recovery

    func rebuildSession() {

        if session.isRunning {
            session.stopRunning()
        }

        session.beginConfiguration()

        for input in session.inputs {
            session.removeInput(input)
        }

        for output in session.outputs {
            session.removeOutput(output)
        }

        session.commitConfiguration()

        frameQueue.sync {
            receiver.resetForNewSession()
        }

        isConfigured = false
    }
}

// MARK: - Public Camera Manager

@MainActor
final class CameraManager: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var status = "Camera stopped"
    @Published private(set) var gazeState: GazeState = .unknown

    private let sensitivity = SensitivityStore()

    private lazy var cameraSession = CameraSessionActor(
        sensitivity: sensitivity
    ) { [weak self] state in

        Task { @MainActor [weak self] in

            guard let self,
                  self.wantsRunning,
                  !self.isSleeping else {
                return
            }

            self.gazeState = state
        }
    }

    private var operationTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    private var generation = 0

    private var wantsRunning = false
    private var isSleeping = false
    private var resumeAfterWake = false

    private var recoveryAttempts = 0

    private let maximumRecoveryAttempts = 3

    // MARK: - Initialization

    init() {
        observeSleepAndWake()
    }

    // MARK: - Sensitivity

    func setYawThreshold(_ value: Double) {
        sensitivity.set(value)
    }

    // MARK: - Start

    func start() {

        guard !wantsRunning else {
            return
        }

        wantsRunning = true
        recoveryAttempts = 0

        guard !isSleeping else {
            resumeAfterWake = true
            status = "Waiting for Mac to wake"
            return
        }

        beginStart()
    }

    private func beginStart() {

        generation += 1
        let currentGeneration = generation

        operationTask?.cancel()
        monitoringTask?.cancel()

        isRunning = false
        gazeState = .unknown
        status = "Starting camera..."

        operationTask = Task { @MainActor in

            let permission = await requestPermission()

            guard !Task.isCancelled,
                  currentGeneration == generation,
                  wantsRunning,
                  !isSleeping else {
                return
            }

            guard permission else {
                wantsRunning = false
                isRunning = false
                gazeState = .unknown
                status = "Camera permission required"
                return
            }

            do {
                try await cameraSession.start()

                guard !Task.isCancelled,
                      currentGeneration == generation,
                      wantsRunning,
                      !isSleeping else {

                    await cameraSession.stop()
                    return
                }

                // Wait up to approximately three seconds
                // for the first camera frame.
                var receivedFrame = false

                for _ in 0..<30 {

                    if await cameraSession.hasReceivedFrame() {
                        receivedFrame = true
                        break
                    }

                    try Task.checkCancellation()

                    try await Task.sleep(
                        for: .milliseconds(100)
                    )
                }

                guard receivedFrame else {
                    throw ShroudCameraError.noFrames
                }

                guard !Task.isCancelled,
                      currentGeneration == generation,
                      wantsRunning,
                      !isSleeping else {

                    await cameraSession.stop()
                    return
                }

                isRunning = true
                status = "Camera running"
                recoveryAttempts = 0

                startMonitoring(
                    generation: currentGeneration
                )

            } catch is CancellationError {

                // A newer start/stop operation owns the state.

            } catch {

                guard currentGeneration == generation else {
                    return
                }

                await cameraSession.stop()

                isRunning = false
                gazeState = .unknown

                status = error.localizedDescription

                scheduleRecovery(
                    generation: currentGeneration
                )
            }
        }
    }

    // MARK: - Permission

    private func requestPermission() async -> Bool {

        switch AVCaptureDevice.authorizationStatus(
            for: .video
        ) {

        case .authorized:
            return true

        case .notDetermined:
            return await AVCaptureDevice.requestAccess(
                for: .video
            )

        case .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Frame Monitoring

    private func startMonitoring(generation expected: Int) {

        monitoringTask?.cancel()

        monitoringTask = Task { @MainActor in

            while !Task.isCancelled {

                do {
                    try await Task.sleep(
                        for: .seconds(2)
                    )
                } catch {
                    return
                }

                guard expected == generation,
                      wantsRunning,
                      isRunning,
                      !isSleeping else {
                    return
                }

                let frameAge =
                    await cameraSession.secondsSinceLastFrame()

                if let frameAge, frameAge > 5 {

                    status = "Camera connection lost"
                    isRunning = false
                    gazeState = .unknown

                    await recoverCamera(
                        generation: expected
                    )

                    return
                }
            }
        }
    }

    // MARK: - Camera Recovery

    private func recoverCamera(generation expected: Int) async {

        guard expected == generation,
              wantsRunning,
              !isSleeping else {
            return
        }

        await cameraSession.rebuildSession()

        guard expected == generation,
              wantsRunning,
              !isSleeping else {
            return
        }

        scheduleRecovery(generation: expected)
    }

    private func scheduleRecovery(generation expected: Int) {

        guard expected == generation,
              wantsRunning,
              !isSleeping else {
            return
        }

        guard recoveryAttempts < maximumRecoveryAttempts else {

            wantsRunning = false
            isRunning = false
            gazeState = .unknown

            status = "Camera unavailable — restart protection"

            return
        }

        recoveryAttempts += 1

        status = "Reconnecting camera (\(recoveryAttempts)/3)..."

        operationTask = Task { @MainActor in

            do {
                try await Task.sleep(
                    for: .seconds(2)
                )
            } catch {
                return
            }

            guard !Task.isCancelled,
                  expected == generation,
                  wantsRunning,
                  !isSleeping else {
                return
            }

            beginStart()
        }
    }

    // MARK: - Stop

    func stop() {

        wantsRunning = false
        resumeAfterWake = false

        generation += 1

        operationTask?.cancel()
        monitoringTask?.cancel()

        operationTask = nil
        monitoringTask = nil

        recoveryAttempts = 0

        isRunning = false
        gazeState = .unknown
        status = "Stopping camera..."

        let expected = generation

        Task { @MainActor in

            await cameraSession.stop()

            guard expected == generation,
                  !wantsRunning else {
                return
            }

            status = "Camera stopped"
        }
    }

    // MARK: - Sleep / Wake Notifications

    private func observeSleepAndWake() {

        let workspaceNotifications =
            NSWorkspace.shared.notificationCenter

        workspaceNotifications.publisher(
            for: NSWorkspace.willSleepNotification
        )
        .sink { [weak self] _ in

            Task { @MainActor [weak self] in
                self?.handleSleep()
            }
        }
        .store(in: &cancellables)

        workspaceNotifications.publisher(
            for: NSWorkspace.didWakeNotification
        )
        .sink { [weak self] _ in

            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
        .store(in: &cancellables)
    }

    // MARK: - Sleep Handling

    private func handleSleep() {

        guard !isSleeping else {
            return
        }

        resumeAfterWake = wantsRunning
        isSleeping = true

        generation += 1

        operationTask?.cancel()
        monitoringTask?.cancel()

        operationTask = nil
        monitoringTask = nil

        isRunning = false
        gazeState = .unknown

        status = "Mac sleeping"

        Task { @MainActor in
            await cameraSession.stop()
        }
    }

    // MARK: - Wake Handling

    private func handleWake() {

        guard isSleeping else {
            return
        }

        isSleeping = false

        let shouldResume =
            resumeAfterWake && wantsRunning

        resumeAfterWake = false

        guard shouldResume else {
            status = "Camera stopped"
            return
        }

        status = "Resuming after wake..."

        // Give the camera hardware time to become available.
        generation += 1
        let expected = generation

        operationTask = Task { @MainActor in

            do {
                try await Task.sleep(
                    for: .seconds(2)
                )
            } catch {
                return
            }

            guard !Task.isCancelled,
                  expected == generation,
                  wantsRunning,
                  !isSleeping else {
                return
            }

            recoveryAttempts = 0
            beginStart()
        }
    }
}
