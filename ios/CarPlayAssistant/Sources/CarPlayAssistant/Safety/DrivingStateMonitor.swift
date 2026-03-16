import Combine
import CoreLocation
#if os(iOS)
import CoreMotion
#endif
import Foundation

// MARK: - DrivingStateMonitor

/// Monitors driving state using CoreLocation speed and accelerometer data.
///
/// Requires a consistent state reading for `debounceInterval` seconds before
/// publishing a state change, preventing flickering from momentary speed changes.
public final class DrivingStateMonitor: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// The current confirmed driving state after debouncing.
    @Published public private(set) var currentState: DrivingState = .unknown

    /// Raw speed in meters per second from the most recent location update.
    @Published public private(set) var rawSpeed: CLLocationSpeed = -1

    /// The most recent location, if available.
    @Published public private(set) var currentLocation: CLLocation?

    // MARK: - Configuration

    /// Duration in seconds a state must be consistent before it is confirmed.
    public var debounceInterval: TimeInterval = 3.0

    // MARK: - Speed Thresholds (mph)

    private enum SpeedThresholdMPH {
        static let parked: Double = 3.0
        static let highway: Double = 45.0
    }

    // MARK: - Private Properties

    private let locationManager: CLLocationManager
    #if os(iOS)
    private let motionManager: CMMotionManager
    #endif
    private var vehicleStateProvider: VehicleStateProvider?

    private var pendingState: DrivingState = .unknown
    private var pendingStateTimestamp: Date?
    private var cancellables = Set<AnyCancellable>()
    private var debounceTimer: Timer?

    // MARK: - Initialization

    #if os(iOS)
    /// Creates a driving state monitor.
    /// - Parameters:
    ///   - locationManager: The CLLocationManager to use. Defaults to a new instance.
    ///   - motionManager: The CMMotionManager to use. Defaults to a new instance.
    ///   - vehicleStateProvider: Optional provider to combine with for richer state.
    public init(
        locationManager: CLLocationManager = CLLocationManager(),
        motionManager: CMMotionManager = CMMotionManager(),
        vehicleStateProvider: VehicleStateProvider? = nil
    ) {
        self.locationManager = locationManager
        self.motionManager = motionManager
        self.vehicleStateProvider = vehicleStateProvider
        super.init()

        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        self.locationManager.activityType = .automotiveNavigation
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.pausesLocationUpdatesAutomatically = false

        bindVehicleStateProvider()
    }
    #else
    /// Creates a driving state monitor.
    /// - Parameters:
    ///   - locationManager: The CLLocationManager to use. Defaults to a new instance.
    ///   - vehicleStateProvider: Optional provider to combine with for richer state.
    public init(
        locationManager: CLLocationManager = CLLocationManager(),
        vehicleStateProvider: VehicleStateProvider? = nil
    ) {
        self.locationManager = locationManager
        self.vehicleStateProvider = vehicleStateProvider
        super.init()

        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        self.locationManager.activityType = .automotiveNavigation
        self.locationManager.pausesLocationUpdatesAutomatically = false

        bindVehicleStateProvider()
    }
    #endif

    // MARK: - Public API

    /// Starts monitoring driving state via location and motion updates.
    public func startMonitoring() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            #if os(iOS)
            locationManager.requestWhenInUseAuthorization()
            #endif
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        #if os(iOS)
        case .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        #endif
        default:
            break
        }

        #if os(iOS)
        startAccelerometerUpdates()
        #endif
    }

    /// Stops monitoring and resets state to unknown.
    public func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        #if os(iOS)
        motionManager.stopAccelerometerUpdates()
        #endif
        debounceTimer?.invalidate()
        debounceTimer = nil
        rawSpeed = -1
        currentLocation = nil
        currentState = .unknown
        pendingState = .unknown
        pendingStateTimestamp = nil
    }

    // MARK: - Private Methods

    private func bindVehicleStateProvider() {
        vehicleStateProvider?.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vehicleState in
                guard let self else { return }
                // If the vehicle state provider has a definitive state, use it
                if vehicleState.drivingState != .unknown {
                    self.proposeDrivingState(vehicleState.drivingState)
                }
            }
            .store(in: &cancellables)
    }

    #if os(iOS)
    private func startAccelerometerUpdates() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.5

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Use accelerometer to detect sudden deceleration (potential crash)
            let totalG = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )
            // Severe impact threshold (~4g above normal 1g gravity)
            if totalG > 5.0 {
                self.currentState = .unknown // Will be handled by EmergencyProtocol
            }
        }
    }
    #endif

    /// Proposes a new driving state. If it matches the pending state and has been
    /// consistent for `debounceInterval`, the published `currentState` is updated.
    private func proposeDrivingState(_ proposed: DrivingState) {
        if proposed == currentState {
            // Already in this state; reset pending
            pendingState = proposed
            pendingStateTimestamp = nil
            return
        }

        if proposed == pendingState {
            // Same pending state: check if debounce threshold reached
            if let timestamp = pendingStateTimestamp,
               Date().timeIntervalSince(timestamp) >= debounceInterval {
                currentState = proposed
                pendingStateTimestamp = nil
            }
        } else {
            // New candidate state
            pendingState = proposed
            pendingStateTimestamp = Date()
        }
    }

    private func inferDrivingState(fromSpeedMPS speed: CLLocationSpeed) -> DrivingState {
        guard speed >= 0 else { return .unknown }

        let speedMPH = speed * 2.23694 // m/s to mph
        if speedMPH < SpeedThresholdMPH.parked {
            return .parked
        } else if speedMPH < SpeedThresholdMPH.highway {
            return .city
        } else {
            return .highway
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension DrivingStateMonitor: CLLocationManagerDelegate {

    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        currentLocation = location
        rawSpeed = location.speed

        let proposed = inferDrivingState(fromSpeedMPS: location.speed)
        proposeDrivingState(proposed)
    }

    public func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Location updates may fail temporarily; keep current state.
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        #if os(iOS)
        let authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        let authorized = status == .authorizedAlways || status == .authorized
        #endif
        if authorized {
            manager.startUpdatingLocation()
        }
    }
}
