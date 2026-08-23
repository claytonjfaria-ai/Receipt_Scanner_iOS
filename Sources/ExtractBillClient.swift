import UIKit

/// The response shape `extract-bill` actually returns — matches
/// `tap2know/supabase/functions/extract-bill/schema.ts::ExtractBillResponse` exactly.
/// `amount`/`billing_date` are nullable by design (§4.2: a reference document like an ATIC
/// packet has no amount due and sometimes no date); `company_name` is the only field the
/// whole design depends on always being present.
struct BillExtractionResult: Decodable {
    let companyName: String
    let amount: Double?
    let billingDate: String?

    enum CodingKeys: String, CodingKey {
        case companyName = "company_name"
        case amount
        case billingDate = "billing_date"
    }
}

enum ExtractBillError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase isn't configured on this build. See secrets.env.example."
        case .invalidResponse:
            return "Unexpected response from the extraction service."
        case .server(let message):
            return message
        }
    }
}

/// Calls the `extract-bill` Edge Function — plan §4.2's "extract-by-value, not by-reference"
/// design: the phone sends image bytes directly, nothing is persisted server-side, no
/// receipt-style Storage round trip.
enum ExtractBillClient {
    static func extract(page: UIImage, accessToken: String) async throws -> BillExtractionResult {
        guard
            let baseURL = Secrets.supabaseURL,
            let anonKey = Secrets.supabaseAnonKey
        else { throw ExtractBillError.notConfigured }

        let encoded = try ExtractionImageEncoder.encode(page)
        let body: [String: String] = [
            "mime_type": encoded.mimeType,
            "image_base64": encoded.base64,
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/extract-bill"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExtractBillError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            // The function's own error shape is `{ "error": "..." }` (index.ts's jsonResponse),
            // distinct from GoTrue's `{ "error_description"/"msg" }` shape — a separate,
            // narrower decode rather than reusing SupabaseErrorResponse.
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw ExtractBillError.server(message ?? "Extraction failed (\(http.statusCode))")
        }

        return try JSONDecoder().decode(BillExtractionResult.self, from: data)
    }
}
