import Foundation

struct Account: Decodable {
    let name: String
    let role: String
    var isAdmin: Bool { role == "admin" }
}

struct Session: Decodable {
    let account: Account
    let token: String
}

struct Service: Decodable, Identifiable {
    let id: String
    let name: String
    let duration: Int
    let price: Int
    let icon: String
}

struct Master: Decodable, Identifiable {
    let id: String
    let name: String
}

struct Catalog: Decodable {
    let services: [Service]
    let masters: [Master]
    let days: [String]
    let defaultDay: String
}

struct Slot: Decodable, Identifiable {
    let startsAt: String
    let endsAt: String
    var id: String { startsAt }
}

struct Booking: Decodable, Identifiable {
    let id: Int
    let clientName: String
    let serviceName: String
    let masterName: String
    let startsAt: String
    let endsAt: String
}

struct APIError: LocalizedError, Decodable {
    let message: String
    var status: Int? = nil
    var errorDescription: String? { message }
    private enum CodingKeys: String, CodingKey { case message }
}

struct API {
    let baseURL = URL(string: "http://127.0.0.1:8080/api/")!

    func request<Value: Decodable>(
        _ path: String, method: String = "GET", token: String? = nil,
        query: [String: String] = [:], body: [String: String]? = nil
    ) async throws -> Value {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.httpMethod = method
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            throw APIError(message: "Сервер NEK недоступен. Проверьте, что он запущен, и повторите попытку.")
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw APIError(message: "Сервер вернул неизвестный ответ.")
        }
        let decoder = JSONDecoder()
        guard (200..<300).contains(status) else {
            var error = (try? decoder.decode(APIError.self, from: data))
                ?? APIError(message: "Ошибка сервера (\(status)).")
            error.status = status
            throw error
        }
        return try decoder.decode(Value.self, from: data)
    }

    func signOut(_ token: String) async throws {
        let _: [String: String] = try await request("session", method: "DELETE", token: token)
    }
}

enum StudioDate {
    static let zone = TimeZone(identifier: "Asia/Dushanbe")!

    static func time(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func day(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw) else { return raw }
        formatter.dateFormat = "d MMM, EEE"
        return formatter.string(from: date)
    }

    static func bookingDay(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return day(formatter.string(from: date))
    }
}
