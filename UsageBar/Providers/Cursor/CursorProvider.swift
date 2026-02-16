import Foundation

/// Cursor IDE usage provider
/// Reads auth from local SQLite DB, fetches usage from cursor.com API
///
/// Detection: ~/Library/Application Support/Cursor/
/// Auth: JWT from state.vscdb → session cookie
/// Data: cursor.com/api/usage + monthly invoice
final class CursorProvider: UsageProvider {
    let id = "cursor"
    let name = "Cursor"
    let iconName = "cursorarrow.click.2"
    let brandColorHex = "#000000"
    var isEnabled: Bool = true

    let apiKeyDescription = "No API key needed! Reads credentials from your local Cursor installation."
    let apiKeyPlaceholder = ""

    /// Detected if Cursor is installed and has auth credentials
    var isConfigured: Bool {
        CursorAuthReader.isInstalled && CursorAuthReader.accessToken != nil
    }

    /// Whether Cursor is installed (even if not logged in)
    static var isInstalled: Bool {
        CursorAuthReader.isInstalled
    }

    /// Current plan type
    var planType: String? {
        // Try to read cached plan from UserDefaults
        UserDefaults.standard.string(forKey: "cursor-plan-type")
    }

    // MARK: - UsageProvider

    func fetchUsage(for period: UsagePeriod) async throws -> UsageData {
        guard let cookie = CursorAuthReader.sessionCookie else {
            throw ProviderError.notConfigured
        }

        let headers = [
            "Cookie": cookie,
            "Content-Type": "application/json",
        ]

        // Fetch usage stats and monthly invoice in parallel
        async let usageTask = fetchUsageStats(headers: headers)
        async let invoiceTask = fetchMonthlyInvoice(headers: headers, period: period)

        let (usage, invoice) = try await (usageTask, invoiceTask)

        // Build breakdown from invoice items (detailed per-model)
        var breakdown: [UsageBreakdown] = []
        var totalInput = 0
        var totalOutput = 0
        var totalCost: Decimal = 0

        if let items = invoice?.items {
            for item in items {
                let model = item.model ?? item.description ?? "unknown"
                let input = item.inputTokens ?? 0
                let output = item.outputTokens ?? 0
                let cost = Decimal(item.amountCents ?? 0) / 100

                totalInput += input
                totalOutput += output
                totalCost += cost

                breakdown.append(UsageBreakdown(
                    model: model,
                    costUSD: cost,
                    inputTokens: input,
                    outputTokens: output,
                    cacheReadTokens: 0,
                    cacheCreationTokens: 0
                ))
            }
        }

        // Use usage-based total cost if invoice didn't have it
        if totalCost == 0 {
            totalCost = Decimal(usage?.usageBasedPricing?.totalCost ?? 0)
        }

        // If no token breakdown, create a summary from request counts
        if breakdown.isEmpty, let premium = usage?.premiumRequests {
            breakdown.append(UsageBreakdown(
                model: "Premium Requests",
                costUSD: totalCost,
                inputTokens: premium.current ?? 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreationTokens: 0
            ))
            totalInput = premium.current ?? 0
        }

        return UsageData(
            provider: name,
            period: period,
            totalCostUSD: totalCost,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            breakdown: breakdown.sorted { $0.totalTokens > $1.totalTokens },
            dailyTrend: [],
            fetchedAt: Date()
        )
    }

    func validate() async throws -> Bool {
        guard CursorAuthReader.isInstalled else { return false }
        guard CursorAuthReader.accessToken != nil else { return false }

        // Try a lightweight API call
        guard let cookie = CursorAuthReader.sessionCookie else { return false }
        let headers = ["Cookie": cookie]

        guard let userId = CursorAuthReader.userId,
              let url = URL(string: "https://www.cursor.com/api/usage?user=\(userId)") else {
            return false
        }

        _ = try await NetworkClient.shared.get(
            url: url,
            headers: headers,
            responseType: CursorUsageResponse.self
        )
        return true
    }

    // MARK: - API Calls

    private func fetchUsageStats(headers: [String: String]) async throws -> CursorUsageResponse? {
        guard let userId = CursorAuthReader.userId,
              let url = URL(string: "https://www.cursor.com/api/usage?user=\(userId)") else {
            return nil
        }

        return try? await NetworkClient.shared.get(
            url: url,
            headers: headers,
            responseType: CursorUsageResponse.self
        )
    }

    private func fetchMonthlyInvoice(
        headers: [String: String],
        period: UsagePeriod
    ) async throws -> CursorInvoiceResponse? {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: period.startDate)
        let year = calendar.component(.year, from: period.startDate)

        guard let url = URL(string: "https://www.cursor.com/api/dashboard/get-monthly-invoice") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: Any] = [
            "month": month,
            "year": year,
            "includeUsageEvents": true,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(CursorInvoiceResponse.self, from: data)
        } catch {
            return nil
        }
    }
}
