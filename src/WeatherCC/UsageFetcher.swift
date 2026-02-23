// meta: created=2026-02-21 updated=2026-02-23 checked=2026-02-21
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

    // MARK: - Org ID (Swift cookie store + JS document.cookie fallback)

    @MainActor
    static func readOrgId(from webView: WKWebView) async throws -> String {
        // Stage 1: Swift cookie store
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        if let orgCookie = cookies.first(where: {
            $0.name == "lastActiveOrg" && $0.domain.hasSuffix("claude.ai")
        }) {
            return orgCookie.value
        }
        // Stage 2: JS document.cookie fallback
        let js = "document.cookie.split('; ').find(c => c.startsWith('lastActiveOrg='))?.split('=')[1] || ''"
        if let result = try? await webView.evaluateJavaScript(js) as? String, !result.isEmpty {
            return result
        }
        throw UsageFetchError.scriptFailed("Missing organization id")
    }

    // MARK: - Public

    @MainActor
    static func fetch(from webView: WKWebView) async throws -> UsageResult {
        // org ID extraction is done inside the JS script (4-stage fallback)
        let raw = try await webView.callAsyncJavaScript(
            usageScript, contentWorld: .page
        )

        guard let jsonString = raw as? String else {
            throw UsageFetchError.decodingFailed
        }

        // Log response to both NSLog and file for diagnostics
        NSLog("[WeatherCC] API response: %@", jsonString)
        let logLine = "\(ISO8601DateFormatter().string(from: Date())) API response: \(jsonString)\n"
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCC-debug.log")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(logLine.data(using: .utf8)!)
            handle.closeFile()
        }
        return try parse(jsonString: jsonString)
    }

    // MARK: - JSON Parsing (testable without WebView)

    /// Parse API response JSON string into UsageResult.
    /// Extracted from fetch() so it can be unit tested with real API response JSON.
    static func parse(jsonString: String) throws -> UsageResult {
        guard let data = jsonString.data(using: .utf8) else {
            throw UsageFetchError.decodingFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let error = json["__error"] as? String {
            throw UsageFetchError.scriptFailed(error)
        }

        // API has two known formats:
        // Format A (current): {"five_hour":{"utilization":25,"resets_at":"ISO8601"},"seven_day":{...}}
        // Format B (documented): {"windows":{"5h":{"limit":N,"remaining":N,"resets_at":unixTs},"7d":{...}}}
        let fiveH: [String: Any]?
        let sevenD: [String: Any]?
        if let windows = json["windows"] as? [String: Any] {
            // Format B
            fiveH = windows["5h"] as? [String: Any]
            sevenD = windows["7d"] as? [String: Any]
        } else {
            // Format A
            fiveH = json["five_hour"] as? [String: Any]
            sevenD = json["seven_day"] as? [String: Any]
        }

        return UsageResult(
            fiveHourPercent: parsePercent(fiveH),
            sevenDayPercent: parsePercent(sevenD),
            fiveHourResetsAt: parseResetsAt(fiveH?["resets_at"]),
            sevenDayResetsAt: parseResetsAt(sevenD?["resets_at"]),
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
        let claudeCookies = cookies.filter { $0.domain.hasSuffix("claude.ai") }
        NSLog("[WeatherCC] hasValidSession: %d cookies total, %d claude.ai", cookies.count, claudeCookies.count)
        let now = Date()
        let hasSession = cookies.contains {
            $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai")
                && ($0.expiresDate.map { $0 > now } ?? true)
        }
        if !hasSession {
            let names = claudeCookies.map(\.name).joined(separator: ", ")
            NSLog("[WeatherCC] hasValidSession: NO sessionKey found. claude.ai cookies: %@", names)
        }
        return hasSession
    }

    // MARK: - JavaScript (org ID extraction + usage API fetch in one script)

    private static let usageScript = """
    return (async () => {
      try {
        const diag = [];
        let orgId = null;

        // Stage 1: document.cookie
        const cookieMatch = document.cookie.match(/lastActiveOrg=([^;]+)/);
        if (cookieMatch) {
          orgId = cookieMatch[1].trim();
          diag.push("S1:OK");
        } else {
          diag.push("S1:MISS(cookies=" + document.cookie.split(";").length + ")");
        }

        // Stage 2: performance API (resource URLs containing /api/organizations/{UUID}/)
        if (!orgId) {
          const uuidPattern = /\\/api\\/organizations\\/([0-9a-f-]{36})\\//;
          const entries = performance.getEntriesByType("resource");
          diag.push("S2:entries=" + entries.length);
          for (let i = entries.length - 1; i >= 0; i--) {
            const m = entries[i].name.match(uuidPattern);
            if (m) { orgId = m[1]; diag.push("S2:OK"); break; }
          }
          if (!orgId) diag.push("S2:MISS");
        }

        // Stage 3: HTML content
        if (!orgId) {
          const htmlMatch = document.documentElement.innerHTML.match(
            /\\/api\\/organizations\\/([0-9a-f-]{36})\\//
          );
          if (htmlMatch) { orgId = htmlMatch[1]; diag.push("S3:OK"); }
          else diag.push("S3:MISS");
        }

        // Stage 4: /api/organizations endpoint
        if (!orgId) {
          const orgResp = await fetch("https://claude.ai/api/organizations", {
            credentials: "include",
            headers: { "Accept": "application/json" }
          });
          diag.push("S4:HTTP" + orgResp.status);
          if (orgResp.ok) {
            const orgs = await orgResp.json();
            if (Array.isArray(orgs) && orgs.length > 0) {
              orgId = orgs[0].uuid || orgs[0].id;
              diag.push("S4:OK");
            } else {
              diag.push("S4:EMPTY(len=" + (Array.isArray(orgs) ? orgs.length : typeof orgs) + ")");
            }
          }
        }

        if (!orgId) throw new Error("Missing organization id [" + diag.join(",") + "]");

        // Fetch usage API
        diag.push("orgId=" + orgId.substring(0, 8) + "...");
        const response = await fetch(
          "https://claude.ai/api/organizations/" + orgId + "/usage",
          { method: "GET", credentials: "include", headers: { "Accept": "application/json" } }
        );
        if (!response.ok) throw new Error("HTTP " + response.status + " [" + diag.join(",") + "]");
        const body = await response.json();
        body.__diag = diag.join(",");
        return JSON.stringify(body);
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

    // MARK: - Usage Percent Parsing

    /// Parse usage percent from a window dict.
    /// Format A: {"utilization": 25} → 25.0 (direct percentage)
    /// Format B: {"limit": 100, "remaining": 75} → 25.0 (calculated)
    static func parsePercent(_ window: [String: Any]?) -> Double? {
        guard let window else { return nil }
        // Format A: utilization field (direct percentage)
        if let util = (window["utilization"] as? Double) ?? (window["utilization"] as? Int).map(Double.init) {
            return util
        }
        // Format B: limit/remaining fields
        return calcPercent(limit: window["limit"], remaining: window["remaining"])
    }

    /// Calculate usage percent from limit and remaining values.
    /// Returns nil if inputs are invalid (nil, non-numeric, or zero limit).
    static func calcPercent(limit: Any?, remaining: Any?) -> Double? {
        guard let l = (limit as? Double) ?? (limit as? Int).map(Double.init),
              let r = (remaining as? Double) ?? (remaining as? Int).map(Double.init),
              l > 0 else { return nil }
        return (l - r) / l * 100.0
    }

    // MARK: - resets_at Parsing (handles both Unix timestamp and ISO 8601 string)

    /// Parse resets_at from either Unix seconds (number) or ISO 8601 string.
    static func parseResetsAt(_ value: Any?) -> Date? {
        // Format B: Unix timestamp (number)
        if let ts = value as? Double { return Date(timeIntervalSince1970: ts) }
        if let ts = value as? Int { return Date(timeIntervalSince1970: Double(ts)) }
        // Format A: ISO 8601 string
        if let str = value as? String { return parseResetDate(str) }
        return nil
    }

    /// Parse a Unix timestamp (seconds since epoch) to Date.
    static func parseUnixTimestamp(_ value: Any?) -> Date? {
        if let ts = value as? Double {
            return Date(timeIntervalSince1970: ts)
        }
        if let ts = value as? Int {
            return Date(timeIntervalSince1970: Double(ts))
        }
        return nil
    }

    // MARK: - ISO 8601 Date Parsing (legacy — kept for existing tests)

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
