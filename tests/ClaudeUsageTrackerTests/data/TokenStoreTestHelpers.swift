import Foundation

// MARK: - Shared helpers for TokenStoreTests and TokenStoreSupplementTests

enum TokenStoreTestHelpers {
    static func writeJSONLFile(name: String, lines: [String], in directory: URL) -> URL {
        let url = directory.appendingPathComponent(name)
        let content = lines.joined(separator: "\n")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func makeAssistantLine(
        requestId: String,
        timestamp: String = "2026-02-22T10:00:00.000Z",
        model: String = "claude-sonnet-4-6",
        inputTokens: Int = 100,
        outputTokens: Int = 200
    ) -> String {
        return """
        {"type":"assistant","requestId":"\(requestId)","timestamp":"\(timestamp)","message":{"model":"\(model)","usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
        """
    }
}
