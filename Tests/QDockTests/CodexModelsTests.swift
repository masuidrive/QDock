import XCTest
@testable import QDock

/// Decoding tests for codex app-server JSON-RPC responses.
/// Production decodes these with a default JSONDecoder (explicit legacy
/// CodingKeys handle snake_case), so these tests do the same.
final class CodexModelsTests: XCTestCase {

    private func decode(_ json: String) throws -> JsonRpcResponse {
        try JSONDecoder().decode(JsonRpcResponse.self, from: Data(json.utf8))
    }

    func testModernCamelCaseMultiBucketResponse() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "id": 2,
          "result": {
            "rateLimits": {
              "limitId": "codex",
              "limitName": "Codex",
              "primary": { "usedPercent": 42.5, "windowDurationMins": 300, "resetsAt": 1784060000 },
              "secondary": { "usedPercent": 13, "windowDurationMins": 10080, "resetsAt": 1784560000 },
              "credits": { "hasCredits": true, "unlimited": false, "balance": "250" },
              "planType": "plus",
              "rateLimitReachedType": null
            },
            "rateLimitsByLimitId": {
              "codex": {
                "limitId": "codex",
                "primary": { "usedPercent": 42.5, "windowDurationMins": 300, "resetsAt": 1784060000 },
                "secondary": { "usedPercent": 13, "windowDurationMins": 10080, "resetsAt": 1784560000 },
                "planType": "plus"
              },
              "other": {
                "limitId": "other",
                "primary": { "usedPercent": 1, "windowDurationMins": 300, "resetsAt": 1784060000 }
              }
            }
          }
        }
        """
        let response = try decode(json)
        let limits = try XCTUnwrap(response.result?.resolvedRateLimits)

        XCTAssertEqual(limits.limitId, "codex", "must prefer the metered codex bucket")
        XCTAssertEqual(limits.primary?.usedPercent, 42.5)
        XCTAssertEqual(limits.primary?.windowDurationMins, 300)
        XCTAssertEqual(limits.primary?.resetsAt, 1_784_060_000)
        XCTAssertEqual(limits.secondary?.usedPercent, 13)
        XCTAssertEqual(limits.planType, "plus")

        let credits = try XCTUnwrap(response.result?.rateLimits?.credits)
        XCTAssertEqual(credits.hasCredits, true)
        XCTAssertEqual(credits.unlimited, false)
        XCTAssertEqual(credits.balance, 250, "numeric-string balances must parse")
    }

    func testLegacySnakeCaseResponse() throws {
        let json = """
        {
          "jsonrpc": "2.0",
          "id": 7,
          "result": {
            "rate_limits": {
              "limit_id": "codex",
              "primary": { "used_percent": 80, "window_duration_mins": 300, "resets_at": 1784060000 },
              "secondary": { "used_percent": "55.5", "window_duration_mins": 10080, "resets_at": 1784560000 },
              "plan_type": "pro"
            }
          }
        }
        """
        let response = try decode(json)
        let limits = try XCTUnwrap(response.result?.resolvedRateLimits)

        XCTAssertEqual(limits.limitId, "codex")
        XCTAssertEqual(limits.primary?.usedPercent, 80)
        XCTAssertEqual(limits.secondary?.usedPercent, 55.5, "string percents must parse")
        XCTAssertEqual(limits.planType, "pro")
    }

    func testErrorEnvelope() throws {
        let json = """
        { "jsonrpc": "2.0", "id": 3, "error": { "code": -32601, "message": "method not found" } }
        """
        let response = try decode(json)
        XCTAssertEqual(response.error?.code, -32601)
        XCTAssertNil(response.result)
    }
}
