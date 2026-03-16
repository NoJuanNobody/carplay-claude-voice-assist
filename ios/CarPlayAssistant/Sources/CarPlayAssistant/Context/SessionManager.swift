import Foundation

// MARK: - Session

/// Represents an active voice assistant session.
public struct Session: Sendable {
    /// Unique session identifier.
    public let id: String

    /// Authentication token for this session.
    public let token: String

    /// Timestamp when the session was started.
    public let startedAt: Date

    public init(id: String, token: String, startedAt: Date) {
        self.id = id
        self.token = token
        self.startedAt = startedAt
    }
}

// MARK: - AssistantResponse

/// Represents a response from the Claude assistant backend.
public struct AssistantResponse: Sendable {
    /// The text response from the assistant.
    public let text: String

    /// Any tool calls the assistant requested (e.g. navigation, media playback).
    public let toolCalls: [ToolCall]

    /// Round-trip latency in milliseconds.
    public let latencyMs: Int

    public init(text: String, toolCalls: [ToolCall] = [], latencyMs: Int = 0) {
        self.text = text
        self.toolCalls = toolCalls
        self.latencyMs = latencyMs
    }
}

// MARK: - ToolCall

/// Represents a tool invocation requested by the assistant.
public struct ToolCall: Sendable {
    /// The tool name (e.g. "navigate", "play_music").
    public let name: String

    /// The tool parameters as a JSON-compatible dictionary encoded as Data.
    public let parametersJSON: Data

    public init(name: String, parametersJSON: Data = Data()) {
        self.name = name
        self.parametersJSON = parametersJSON
    }
}

// MARK: - SessionManagerError

/// Errors that can occur during session management.
public enum SessionManagerError: Error, CustomStringConvertible {
    case noActiveSession
    case sessionStartFailed(Error)
    case messageSendFailed(Error)
    case invalidResponse

    public var description: String {
        switch self {
        case .noActiveSession:
            return "No active session. Call startSession() first."
        case .sessionStartFailed(let error):
            return "Failed to start session: \(error.localizedDescription)"
        case .messageSendFailed(let error):
            return "Failed to send message: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the backend."
        }
    }
}

// MARK: - SessionManager

/// Manages the lifecycle of voice assistant sessions with the backend API.
///
/// Handles session creation, message exchange, and teardown. Each session is
/// authenticated with a unique token for secure communication.
public final class SessionManager {

    // MARK: - Properties

    /// The currently active session, if any.
    public private(set) var currentSession: Session?

    /// The base URL for the assistant backend API.
    private let baseURL: URL

    /// The URLSession used for network requests.
    private let urlSession: URLSession

    /// API key for authenticating with the backend.
    private let apiKey: String

    // MARK: - Initialization

    /// Creates a session manager.
    /// - Parameters:
    ///   - baseURL: The base URL of the backend API.
    ///   - apiKey: The API key for authentication.
    ///   - urlSession: The URL session to use. Defaults to `.shared`.
    public init(
        baseURL: URL,
        apiKey: String,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    // MARK: - Session Lifecycle

    /// Starts a new voice assistant session.
    ///
    /// - Parameter vehicleId: An optional vehicle identifier for vehicle-specific context.
    /// - Returns: The newly created session.
    /// - Throws: ``SessionManagerError/sessionStartFailed(_:)`` if the request fails.
    @discardableResult
    public func startSession(vehicleId: String? = nil) async throws -> Session {
        let url = baseURL.appendingPathComponent("v1/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [:]
        if let vehicleId {
            body["vehicle_id"] = vehicleId
        }

        if !body.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw SessionManagerError.sessionStartFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SessionManagerError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["session_id"] as? String,
              let token = json["token"] as? String else {
            throw SessionManagerError.invalidResponse
        }

        let session = Session(id: id, token: token, startedAt: Date())
        currentSession = session
        return session
    }

    /// Ends the current session.
    ///
    /// - Throws: ``SessionManagerError/noActiveSession`` if there is no active session.
    public func endSession() async throws {
        guard let session = currentSession else {
            throw SessionManagerError.noActiveSession
        }

        let url = baseURL.appendingPathComponent("v1/sessions/\(session.id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        _ = try? await urlSession.data(for: request)
        currentSession = nil
    }

    /// Sends a user message to the assistant and returns the response.
    ///
    /// - Parameter text: The user's transcribed speech text.
    /// - Returns: The assistant's response including text and any tool calls.
    /// - Throws: ``SessionManagerError`` if the request fails.
    public func sendMessage(_ text: String) async throws -> AssistantResponse {
        guard let session = currentSession else {
            throw SessionManagerError.noActiveSession
        }

        let url = baseURL.appendingPathComponent("v1/sessions/\(session.id)/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["content": text, "role": "user"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let startTime = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw SessionManagerError.messageSendFailed(error)
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SessionManagerError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["text"] as? String else {
            throw SessionManagerError.invalidResponse
        }

        var toolCalls: [ToolCall] = []
        if let toolCallsArray = json["tool_calls"] as? [[String: Any]] {
            for toolCallJSON in toolCallsArray {
                if let name = toolCallJSON["name"] as? String {
                    let params = toolCallJSON["parameters"] ?? [:]
                    let paramsData = (try? JSONSerialization.data(withJSONObject: params)) ?? Data()
                    toolCalls.append(ToolCall(name: name, parametersJSON: paramsData))
                }
            }
        }

        return AssistantResponse(text: responseText, toolCalls: toolCalls, latencyMs: latencyMs)
    }
}
