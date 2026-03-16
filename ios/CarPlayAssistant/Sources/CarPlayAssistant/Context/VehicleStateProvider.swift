import Combine
import CoreLocation
import Foundation

// MARK: - DrivingState

/// Represents the current driving state of the vehicle.
public enum DrivingState: String, Sendable {
    case parked
    case city
    case highway
    case unknown
}

// MARK: - VehicleState

/// A snapshot of the current vehicle state.
public struct VehicleState: Sendable {
    /// Current speed in meters per second. Negative if unavailable.
    public let currentSpeed: CLLocationSpeed

    /// Current location, if available.
    public let currentLocation: CLLocation?

    /// The inferred driving state.
    public let drivingState: DrivingState

    public init(
        currentSpeed: CLLocationSpeed = -1,
        currentLocation: CLLocation? = nil,
        drivingState: DrivingState = .unknown
    ) {
        self.currentSpeed = currentSpeed
        self.currentLocation = currentLocation
        self.drivingState = drivingState
    }
}

// MARK: - VehicleStateProvider

/// Reads vehicle state from CoreLocation and publishes changes via Combine.
///
/// Infers the driving state from the current speed:
/// - Parked: speed < 2 m/s (~4.5 mph)
/// - City: 2-25 m/s (~4.5-56 mph)
/// - Highway: > 25 m/s (~56 mph)
public final class VehicleStateProvider: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// The current speed in meters per second. Negative if unavailable.
    @Published public private(set) var currentSpeed: CLLocationSpeed = -1

    /// The current location, if available.
    @Published public private(set) var currentLocation: CLLocation?

    /// The inferred driving state based on speed.
    @Published public private(set) var drivingState: DrivingState = .unknown

    /// A combined vehicle state snapshot publisher.
    public var statePublisher: AnyPublisher<VehicleState, Never> {
        Publishers.CombineLatest3($currentSpeed, $currentLocation, $drivingState)
            .map { speed, location, state in
                VehicleState(currentSpeed: speed, currentLocation: location, drivingState: state)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let locationManager: CLLocationManager

    /// Speed thresholds in m/s for driving state inference.
    private enum SpeedThreshold {
        static let parked: CLLocationSpeed = 2.0       // ~4.5 mph
        static let highway: CLLocationSpeed = 25.0     // ~56 mph
    }

    // MARK: - Initialization

    /// Creates a vehicle state provider.
    /// - Parameter locationManager: The location manager to use. Defaults to a new instance.
    public init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        self.locationManager.activityType = .automotiveNavigation
        #if os(iOS)
        self.locationManager.allowsBackgroundLocationUpdates = true
        #endif
        self.locationManager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Public API

    /// Starts monitoring vehicle state. Requests location authorization if needed.
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
    }

    /// Stops monitoring vehicle state.
    public func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        currentSpeed = -1
        currentLocation = nil
        drivingState = .unknown
    }

    // MARK: - Driving State Inference

    private func inferDrivingState(from speed: CLLocationSpeed) -> DrivingState {
        guard speed >= 0 else { return .unknown }

        if speed < SpeedThreshold.parked {
            return .parked
        } else if speed < SpeedThreshold.highway {
            return .city
        } else {
            return .highway
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension VehicleStateProvider: CLLocationManagerDelegate {

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        currentSpeed = location.speed
        drivingState = inferDrivingState(from: location.speed)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
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
