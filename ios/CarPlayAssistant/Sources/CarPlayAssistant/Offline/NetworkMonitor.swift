import Foundation
import Network

// MARK: - ConnectionType

/// The type of network connection currently available.
public enum ConnectionType: String, Sendable {
    case wifi
    case cellular
    case wiredEthernet
    case none
}

// MARK: - ConnectionQuality

/// A qualitative assessment of the current network connection.
public enum ConnectionQuality: String, Sendable {
    /// Strong connection, typically Wi-Fi.
    case good
    /// Moderate connection, typically cellular with adequate signal.
    case fair
    /// Weak connection, cellular with low signal or constrained path.
    case poor
    /// No network connection available.
    case none
}

// MARK: - NetworkMonitorDelegate

/// Delegate protocol for receiving network connectivity changes.
public protocol NetworkMonitorDelegate: AnyObject {
    /// Called when the network connection status changes.
    /// - Parameters:
    ///   - isConnected: Whether the device currently has network connectivity.
    ///   - connectionType: The type of connection.
    ///   - quality: The assessed quality of the connection.
    func didChangeConnectionStatus(isConnected: Bool, connectionType: ConnectionType, quality: ConnectionQuality)
}

// MARK: - NetworkMonitor

/// Monitors network connectivity using NWPathMonitor.
///
/// Provides real-time updates about network availability, connection type,
/// and connection quality. Notifies its delegate whenever the status changes.
public final class NetworkMonitor {

    // MARK: - Properties

    /// Whether the device currently has network connectivity.
    public private(set) var isConnected: Bool = false

    /// The current network connection type.
    public private(set) var connectionType: ConnectionType = .none

    /// The assessed quality of the current connection.
    public private(set) var quality: ConnectionQuality = .none

    /// Delegate to receive connection status change callbacks.
    public weak var delegate: NetworkMonitorDelegate?

    private let monitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var isMonitoring: Bool = false

    // MARK: - Initialization

    /// Creates a network monitor.
    /// - Parameter queue: The dispatch queue for path update callbacks. Defaults to a dedicated queue.
    public init(queue: DispatchQueue = DispatchQueue(label: "com.carplay.assistant.network.monitor", qos: .utility)) {
        self.monitor = NWPathMonitor()
        self.monitorQueue = queue
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Starts monitoring network connectivity.
    ///
    /// Path updates are delivered on the monitor queue, then delegate callbacks
    /// are dispatched to the main queue.
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        monitor.start(queue: monitorQueue)
    }

    /// Stops monitoring network connectivity.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
    }

    /// Returns a snapshot of the current network status.
    /// - Returns: A tuple of (isConnected, connectionType, quality).
    public func currentStatus() -> (isConnected: Bool, connectionType: ConnectionType, quality: ConnectionQuality) {
        (isConnected, connectionType, quality)
    }

    // MARK: - Private

    private func handlePathUpdate(_ path: NWPath) {
        let newIsConnected = path.status == .satisfied
        let newConnectionType = resolveConnectionType(path)
        let newQuality = assessQuality(path: path, connectionType: newConnectionType)

        let changed = newIsConnected != isConnected
            || newConnectionType != connectionType
            || newQuality != quality

        isConnected = newIsConnected
        connectionType = newConnectionType
        quality = newQuality

        if changed {
            let connected = isConnected
            let type = connectionType
            let qual = quality

            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didChangeConnectionStatus(
                    isConnected: connected,
                    connectionType: type,
                    quality: qual
                )
            }
        }
    }

    private func resolveConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return .none
        }
    }

    private func assessQuality(path: NWPath, connectionType: ConnectionType) -> ConnectionQuality {
        guard path.status == .satisfied else {
            return .none
        }

        switch connectionType {
        case .wifi:
            return .good
        case .wiredEthernet:
            return .good
        case .cellular:
            // Use path constraints as a proxy for signal quality.
            // isConstrained indicates the path is limited (e.g., Low Data Mode).
            // isExpensive indicates cellular or hotspot.
            if path.isConstrained {
                return .poor
            }
            return .fair
        case .none:
            return .none
        }
    }
}
