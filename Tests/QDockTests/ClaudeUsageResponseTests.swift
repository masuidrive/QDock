import XCTest
@testable import QDock

/// Decoding tests for the Anthropic oauth/usage response.
/// The "modern" fixture is a real (redacted) response captured 2026-07-14.
final class ClaudeUsageResponseTests: XCTestCase {

    private func decode(_ json: String) throws -> ClaudeUsageResponse {
        try NetworkClient.makeAPIDecoder()
            .decode(ClaudeUsageResponse.self, from: Data(json.utf8))
    }

    // MARK: - Modern schema (limits[] array)

    private let modernResponse = """
    {
      "five_hour": {
        "utilization": 58.0,
        "resets_at": "2026-07-14T21:39:59.791719+00:00",
        "limit_dollars": null,
        "used_dollars": null,
        "remaining_dollars": null
      },
      "seven_day": {
        "utilization": 58.0,
        "resets_at": "2026-07-15T12:59:59.791744+00:00",
        "limit_dollars": null,
        "used_dollars": null,
        "remaining_dollars": null
      },
      "seven_day_oauth_apps": null,
      "seven_day_opus": null,
      "seven_day_sonnet": null,
      "extra_usage": {
        "is_enabled": false,
        "monthly_limit": null,
        "used_credits": null,
        "utilization": null,
        "currency": null,
        "decimal_places": null,
        "disabled_reason": null,
        "daily": null,
        "weekly": null
      },
      "limits": [
        {
          "kind": "session",
          "group": "session",
          "percent": 58,
          "severity": "normal",
          "resets_at": "2026-07-14T21:39:59.791719+00:00",
          "scope": null,
          "is_active": true
        },
        {
          "kind": "weekly_all",
          "group": "weekly",
          "percent": 58,
          "severity": "normal",
          "resets_at": "2026-07-15T12:59:59.791744+00:00",
          "scope": null,
          "is_active": false
        },
        {
          "kind": "weekly_scoped",
          "group": "weekly",
          "percent": 49,
          "severity": "normal",
          "resets_at": "2026-07-15T12:59:59.792150+00:00",
          "scope": {
            "model": {
              "id": null,
              "display_name": "Fable"
            },
            "surface": null
          },
          "is_active": false
        }
      ],
      "spend": {
        "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
        "limit": null,
        "percent": 0,
        "severity": "normal",
        "enabled": false
      },
      "member_dashboard_available": false
    }
    """

    func testModernResponseUsesLimitsArray() throws {
        let quota = try decode(modernResponse)
            .toQuotaData(provider: "Claude", planName: "Max 5x", email: nil)

        XCTAssertEqual(quota.windows.count, 3)

        let session = try XCTUnwrap(quota.windows.first { $0.id == "session" })
        XCTAssertEqual(session.usagePercent, 58.0)
        XCTAssertEqual(session.windowDurationMinutes, 300)
        XCTAssertEqual(session.isActive, true)
        XCTAssertEqual(session.severity, "normal")
        XCTAssertNotNil(session.resetsAt, "microsecond ISO8601 timestamps must decode")

        let weekly = try XCTUnwrap(quota.windows.first { $0.id == "weekly" })
        XCTAssertEqual(weekly.displayName, "Weekly (All Models)")
        XCTAssertEqual(weekly.windowDurationMinutes, 10080)

        let fable = try XCTUnwrap(quota.windows.first { $0.id == "weekly-fable" })
        XCTAssertEqual(fable.displayName, "Fable Weekly")
        XCTAssertEqual(fable.usagePercent, 49.0)
        XCTAssertEqual(fable.windowDurationMinutes, 10080)
    }

    func testDisabledExtraUsageYieldsNoCredits() throws {
        let quota = try decode(modernResponse)
            .toQuotaData(provider: "Claude", planName: nil, email: nil)
        XCTAssertNil(quota.usageCredits)
    }

    // MARK: - Legacy schema (no limits[])

    func testLegacyResponseFallsBackWithCorrectLabels() throws {
        let legacy = """
        {
          "five_hour": { "utilization": 33.0, "resets_at": "2026-04-11T07:00:00+00:00" },
          "seven_day": { "utilization": 13.0, "resets_at": "2026-04-17T00:59:59+00:00" },
          "seven_day_opus": { "utilization": 21.0, "resets_at": "2026-04-17T00:59:59+00:00" },
          "seven_day_sonnet": { "utilization": 1.0, "resets_at": "2026-04-17T00:59:59+00:00" }
        }
        """
        let quota = try decode(legacy)
            .toQuotaData(provider: "Claude", planName: nil, email: nil)

        XCTAssertEqual(quota.windows.map(\.id), ["session", "weekly", "weekly-opus", "weekly-sonnet"])
        let opus = try XCTUnwrap(quota.windows.first { $0.id == "weekly-opus" })
        XCTAssertEqual(opus.displayName, "Opus Weekly", "seven_day_opus must not be labeled as Sonnet")
        XCTAssertEqual(quota.windows.first { $0.id == "weekly" }?.displayName, "Weekly")
    }

    // MARK: - Usage credits

    func testEnabledExtraUsageMapsToCredits() throws {
        let json = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2026-07-14T21:00:00+00:00" },
          "extra_usage": {
            "is_enabled": true,
            "monthly_limit": 50,
            "used_credits": 12.5,
            "utilization": 25.0,
            "currency": "USD"
          }
        }
        """
        let quota = try decode(json)
            .toQuotaData(provider: "Claude", planName: nil, email: nil)

        let credits = try XCTUnwrap(quota.usageCredits)
        XCTAssertEqual(credits.usedCredits, 12.5)
        XCTAssertEqual(credits.monthlyLimit, 50)
        XCTAssertEqual(credits.utilization, 25.0)
        XCTAssertEqual(credits.currency, "USD")
    }

    // MARK: - Forward compatibility

    func testUnknownLimitKindIsSurfacedNotDropped() throws {
        let json = """
        {
          "limits": [
            {
              "kind": "monthly_special",
              "group": "monthly",
              "percent": 7,
              "severity": "normal",
              "resets_at": "2026-08-01T00:00:00+00:00",
              "scope": null,
              "is_active": false
            }
          ]
        }
        """
        let quota = try decode(json)
            .toQuotaData(provider: "Claude", planName: nil, email: nil)

        XCTAssertEqual(quota.windows.count, 1)
        XCTAssertEqual(quota.windows.first?.id, "monthly_special")
        XCTAssertEqual(quota.windows.first?.displayName, "Monthly Special")
        XCTAssertEqual(quota.windows.first?.usagePercent, 7)
    }

    // MARK: - Severity escalation

    func testSeverityEscalatesButNeverDowngrades() {
        XCTAssertEqual(UsageLevel.from(percent: 20, severity: "normal"), .low)
        XCTAssertEqual(UsageLevel.from(percent: 20, severity: "warning"), .high)
        XCTAssertEqual(UsageLevel.from(percent: 20, severity: "exceeded"), .critical)
        XCTAssertEqual(UsageLevel.from(percent: 95, severity: "normal"), .critical)
        XCTAssertEqual(UsageLevel.from(percent: 95, severity: nil), .critical)
        XCTAssertEqual(UsageLevel.from(percent: 20, severity: "some_future_value"), .low)
    }
}
