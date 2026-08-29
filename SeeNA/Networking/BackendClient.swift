import Foundation

struct NetworkConfiguration: Sendable {
    let baseURL: URL?
    let appToken: String

    static var bundle: NetworkConfiguration {
        let localSecrets = bundledSecrets()
        let rawURL = localSecrets["SEENA_BACKEND_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SEENA_BACKEND_URL") as? String
        let token = localSecrets["SEENA_APP_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SEENA_APP_TOKEN") as? String
        return NetworkConfiguration(
            baseURL: rawURL.flatMap(URL.init(string:)),
            appToken: token ?? "seena-v0-prototype"
        )
    }

    private static func bundledSecrets() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String] else {
            return [:]
        }
        return values
    }

    static let unavailable = NetworkConfiguration(
        baseURL: nil,
        appToken: "preview"
    )
}

enum TranscriptionMode: String, Codable, Sendable {
    case singleDirection
    case directionBlock
    case readabilityPhrase
    case constrainedChoice
}

struct TranscriptionResponse: Codable, Sendable {
    let valid: Bool
    let mode: TranscriptionMode
    let transcript: String
    let directions: [OptotypeDirection]?
    let choice: String?
    let failureReason: String?

    /// The one unambiguous Landolt-C answer returned by `singleDirection`.
    /// Keeping this validation at the networking boundary prevents a caller
    /// from accidentally accepting a partial or multi-direction transcript.
    var singleDirection: OptotypeDirection? {
        guard valid,
              mode == .singleDirection,
              let directions,
              directions.count == 1 else {
            return nil
        }
        return directions[0]
    }
}

struct ExplanationRequest: Codable, Sendable {
    struct EyeFacts: Codable, Sendable {
        let status: ScreeningStatus
        let quality: QualityLabel
        /// Deterministic values calculated on-device. They are evidence for the
        /// remote consistency check, never values supplied or revised by it.
        let displayedEstimateDiopter: Double?
        let thresholdDistanceMetres: Double?
        let lastFailDiopter: Double?
        let firstPassDiopter: Double?
        let sensorUncertaintyDiopter: Double?
        let repeatabilityDiopter: Double?
    }

    let locale: String
    let rightEye: EyeFacts?
    let leftEye: EyeFacts?
    let comparison: String
    let actionCode: String
    let limitations: [String]
    /// The on-device arithmetic/invariant check. The backend can only report
    /// this evidence; it cannot turn it into a clinical judgement.
    let localMathConsistent: Bool
}

enum ResultVerification: String, Codable, Sendable {
    case consistent
    case reviewRequired
    case notApplicable
}

struct ExplanationResponse: Codable, Sendable {
    let headline: String
    let plainMeaning: String
    let limitations: [String]
    let nextSteps: [String]
    let disclaimer: String
    let verification: ResultVerification
    let usedFallback: Bool?
}

struct AdaptContentRequest: Codable, Sendable {
    let locale: String
    let contentID: String
    let highContrast: Bool
    let readAloud: Bool
    let simplifiedContent: Bool
}

struct AdaptedContentResponse: Codable, Sendable {
    let title: String
    let summary: String
    let steps: [String]
    let deadline: String
    let primaryAction: String
    let readAloudText: String
    let usedFallback: Bool?
}

actor BackendClient {
    private let configuration: NetworkConfiguration
    private let session: URLSession

    init(configuration: NetworkConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func transcribe(
        audioURL: URL,
        mode: TranscriptionMode,
        locale: String = "en-AU",
        phraseID: String? = nil,
        choiceSetID: String? = nil
    ) async throws -> TranscriptionResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "mode", value: mode.rawValue, boundary: boundary)
        body.appendMultipartField(name: "locale", value: locale, boundary: boundary)
        if let phraseID { body.appendMultipartField(name: "phraseId", value: phraseID, boundary: boundary) }
        if let choiceSetID { body.appendMultipartField(name: "choiceSetId", value: choiceSetID, boundary: boundary) }
        let audio = try Data(contentsOf: audioURL)
        body.appendMultipartFile(name: "audio", filename: "response.m4a", mimeType: "audio/mp4", data: audio, boundary: boundary)
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = try makeRequest(path: "/api/transcribe-block", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await sendWithSingleRetry(request)
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    }

    func explain(_ facts: ExplanationRequest) async throws -> ExplanationResponse {
        try await postJSON(path: "/api/explain-result", value: facts, response: ExplanationResponse.self)
    }

    func adapt(_ requestValue: AdaptContentRequest) async throws -> AdaptedContentResponse {
        try await postJSON(path: "/api/adapt-content", value: requestValue, response: AdaptedContentResponse.self)
    }

    func speech(text: String, locale: String = "en-AU") async throws -> Data {
        var request = try makeRequest(path: "/api/speak", method: "POST")
        // Voice guidance must never freeze a hands-free journey behind two
        // long network attempts. If natural speech is not ready promptly, the
        // caller immediately falls back to the best on-device female voice.
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpeechRequest(text: text, locale: locale))
        return try await sendOnce(request)
    }

    private func postJSON<Input: Encodable, Output: Decodable>(path: String, value: Input, response: Output.Type) async throws -> Output {
        var request = try makeRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(value)
        let data = try await sendWithSingleRetry(request)
        return try JSONDecoder().decode(Output.self, from: data)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let baseURL = configuration.baseURL,
              baseURL.scheme == "https",
              let url = URL(string: path, relativeTo: baseURL) else {
            throw BackendError.invalidConfiguration
        }
        var request = URLRequest(url: url, timeoutInterval: 24)
        request.httpMethod = method
        request.setValue(configuration.appToken, forHTTPHeaderField: "X-SEENA-App-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func sendWithSingleRetry(_ request: URLRequest) async throws -> Data {
        var lastError: Error?
        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
                if (200..<300).contains(http.statusCode) { return data }
                if attempt == 0, (http.statusCode == 429 || http.statusCode >= 500) {
                    try await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }
                throw BackendError.serverStatus(http.statusCode)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 0 {
                    try await Task.sleep(nanoseconds: 450_000_000)
                }
            }
        }
        throw lastError ?? BackendError.invalidResponse
    }

    private func sendOnce(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.serverStatus(http.statusCode)
        }
        return data
    }

    enum BackendError: LocalizedError {
        case invalidConfiguration
        case invalidResponse
        case serverStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: return "The SeeNA backend URL is not configured."
            case .invalidResponse: return "The SeeNA backend returned an invalid response."
            case .serverStatus(let status): return "The SeeNA backend returned status \(status)."
            }
        }
    }
}

private struct SpeechRequest: Encodable {
    let text: String
    let locale: String
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        append(Data("\(value)\r\n".utf8))
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append(Data("--\(boundary)\r\n".utf8))
        append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        append(data)
        append(Data("\r\n".utf8))
    }
}
