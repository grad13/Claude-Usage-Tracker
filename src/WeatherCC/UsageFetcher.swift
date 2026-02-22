// meta: created=2026-02-21 updated=2026-02-22 checked=2026-02-21
import Foundation
import WebKit

struct UsageResult {
    var fiveHourPercent: Double?
    var sevenDayPercent: Double?
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?
    var fiveHourStatus: Int?       // 0=within_limit, 1=approaching_limit, 2=exceeded_limit
    var sevenDayStatus: Int?
    var fiveHourLimit: Double?
    var fiveHourRemaining: Double?
    var sevenDayLimit: Double?
    var sevenDayRemaining: Double?
    var rawJSON: String?
}

enum UsageFetchError: LocalizedError {
    case scriptFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let msg): return msg
        case .decodingFailed: return "Failed to decode usage data"
        }
    }

    /// Whether this error indicates an authentication problem
    var isAuthError: Bool {
        switch self {
        case .scriptFailed(let msg):
            let lower = msg.lowercased()
            return lower.contains("missing organization")
                || lower.contains("http 401")
                || lower.contains("http 403")
        case .decodingFailed:
            return false
        }
    }
}

enum UsageFetcher {

    // MARK: - Public

    @MainActor
    static func fetch(from webView: WKWebView) async throws -> UsageResult {
        let raw = try await webView.callAsyncJavaScript(
            usageScript, contentWorld: .page
        )

        guard let jsonString = raw as? String,
              let data = jsonString.data(using: .utf8) else {
            throw UsageFetchError.decodingFailed
        }

        NSLog("[WeatherCC] API response: %@", jsonString)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let error = json["__error"] as? String {
            throw UsageFetchError.scriptFailed(error)
        }

        // API response: {"five_hour":{"utilization":15,"resets_at":"ISO8601"}, "seven_day":{...}, ...}
        let fiveH = json["five_hour"] as? [String: Any]
        let sevenD = json["seven_day"] as? [String: Any]

        return UsageResult(
            fiveHourPercent: fiveH?["utilization"] as? Double,
            sevenDayPercent: sevenD?["utilization"] as? Double,
            fiveHourResetsAt: parseResetDate(fiveH?["resets_at"] as? String),
            sevenDayResetsAt: parseResetDate(sevenD?["resets_at"] as? String),
            fiveHourStatus: parseStatus(fiveH?["status"] as? String),
            sevenDayStatus: parseStatus(sevenD?["status"] as? String),
            fiveHourLimit: fiveH?["limit"] as? Double,
            fiveHourRemaining: fiveH?["remaining"] as? Double,
            sevenDayLimit: sevenD?["limit"] as? Double,
            sevenDayRemaining: sevenD?["remaining"] as? Double,
            rawJSON: jsonString
        )
    }

    // MARK: - Session Check

    @MainActor
    static func hasValidSession(using webView: WKWebView) async -> Bool {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let now = Date()
        return cookies.contains {
            $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai")
                && ($0.expiresDate.map { $0 > now } ?? true)
        }
    }

    // MARK: - JavaScript (org ID + API fetch in one script)

    private static let usageScript = """
    return (async () => {
      try {
        function readCookieValue(name) {
          const pattern = new RegExp("(?:^|; )" + name + "=([^;]*)");
          const match = document.cookie.match(pattern);
          return match ? decodeURIComponent(match[1]) : null;
        }

        function findOrgIdFromResources() {
          const entries = performance.getEntriesByType("resource");
          for (const entry of entries) {
            if (!entry || !entry.name) continue;
            const match = entry.name.match(/\\/api\\/organizations\\/([a-f0-9-]{36})/);
            if (match) return match[1];
          }
          return null;
        }

        function findOrgIdFromHtml() {
          const html = document.documentElement ? document.documentElement.innerHTML : "";
          const match = html.match(/\\/api\\/organizations\\/([a-f0-9-]{36})/);
          return match ? match[1] : null;
        }

        async function findOrgIdFromApi() {
          try {
            const resp = await fetch("https://claude.ai/api/organizations", {
              method: "GET", credentials: "include",
              headers: { "Accept": "application/json" }
            });
            if (!resp.ok) return null;
            const orgs = await resp.json();
            if (Array.isArray(orgs) && orgs.length > 0) return orgs[0].uuid;
          } catch (e) {}
          return null;
        }

        let orgId = readCookieValue("lastActiveOrg")
          || findOrgIdFromResources()
          || findOrgIdFromHtml();
        if (!orgId) {
          orgId = await findOrgIdFromApi();
        }
        if (!orgId) {
          throw new Error("Missing organization id");
        }

        const response = await fetch(
          "https://claude.ai/api/organizations/" + orgId + "/usage",
          {
            method: "GET",
            credentials: "include",
            headers: { "Accept": "application/json" }
          }
        );
        if (!response.ok) throw new Error("HTTP " + response.status);
        return JSON.stringify(await response.json());
      } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return JSON.stringify({ "__error": message });
      }
    })();
    """

    // MARK: - Status Parsing

    static func parseStatus(_ s: String?) -> Int? {
        switch s {
        case "within_limit": return 0
        case "approaching_limit": return 1
        case "exceeded_limit": return 2
        default: return nil
        }
    }

    // MARK: - ISO 8601 Date Parsing (matching AgentLimits reference)

    static func parseResetDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = formatterWithFractional.date(from: value) {
            return date
        }
        if let date = formatterNoFractional.date(from: value) {
            return date
        }
        if let trimmed = trimFractionalSeconds(value),
           let date = formatterWithFractional.date(from: trimmed) {
            return date
        }
        return nil
    }

    static func trimFractionalSeconds(_ value: String) -> String? {
        guard let dotIndex = value.firstIndex(of: ".") else { return nil }
        let fractionStart = value.index(after: dotIndex)
        guard let suffixStart = value[fractionStart...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else {
            return nil
        }
        let fraction = value[fractionStart..<suffixStart]
        if fraction.count <= 3 { return value }
        let trimmedFraction = fraction.prefix(3)
        return String(value[..<fractionStart]) + trimmedFraction + value[suffixStart...]
    }

    private static let formatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let formatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
