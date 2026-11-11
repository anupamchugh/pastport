// The Web tool Connected tools offers, with the same Search1API request the Foundation Lab package made.
// Adapted from Foundation-Models-Framework-Lab (FoundationLabCore), MIT License, Copyright (c) 2025 Rudrank Riyam.
// Carried here so Pastport no longer depends on that package, which another app may pin from a different fork.

import Foundation
import FoundationModels
import FoundationModelsKit

struct Search1WebSearchTool: Tool {
    let name = "searchWeb"
    let description = "Search the web using Search1API's free keyless endpoint"

    @Generable
    struct Arguments: RuntimeCompatibleGenerable {
        @Guide(description: "The search query to look up on the web.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> some PromptRepresentable {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return output(status: "error", query: query, count: 0, summary: "Search query cannot be empty.") }
        do {
            let results = try await search(query: query)
            guard !results.isEmpty else {
                return output(status: "empty", query: query, count: 0, summary: "No results found for \"\(query)\".")
            }
            let summary = results.prefix(5).enumerated().map { index, result in
                "\(index + 1). \(result.title)\n\(result.snippet ?? result.content ?? "No summary available.")\n\(result.link)"
            }.joined(separator: "\n\n")
            return output(status: "success", query: query, count: results.count, summary: summary)
        } catch {
            return output(status: "error", query: query, count: 0, summary: "Web search failed: \(error.localizedDescription)")
        }
    }

    private func output(status: String, query: String, count: Int, summary: String) -> GeneratedContent {
        GeneratedContent(properties: ["status": status, "query": query, "resultCount": count, "summary": summary])
    }

    private func search(query: String) async throws -> [SearchResult] {
        guard let url = URL(string: "https://api.search1api.com/search") else { throw Search1Error.invalidResponse }
        let payload = SearchRequest(query: query, searchService: "google", maxResults: 5, crawlResults: 0, image: false,
                                    includeSites: [], excludeSites: [], language: "en", timeRange: "year")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Search1Error.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw Search1Error.httpStatus(http.statusCode) }
        return try JSONDecoder().decode(SearchResponse.self, from: data).results
    }
}

private struct SearchRequest: Encodable {
    let query: String
    let searchService: String
    let maxResults: Int
    let crawlResults: Int
    let image: Bool
    let includeSites: [String]
    let excludeSites: [String]
    let language: String
    let timeRange: String

    enum CodingKeys: String, CodingKey {
        case query, image, language
        case searchService = "search_service"
        case maxResults = "max_results"
        case crawlResults = "crawl_results"
        case includeSites = "include_sites"
        case excludeSites = "exclude_sites"
        case timeRange = "time_range"
    }
}

private struct SearchResponse: Decodable { let results: [SearchResult] }

private struct SearchResult: Decodable {
    let title: String
    let link: String
    let snippet: String?
    let content: String?
}

private enum Search1Error: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: String(localized: "Invalid response from Search1API.")
        case .httpStatus(401), .httpStatus(403): String(localized: "Search1API keyless access is unavailable right now. Please try again later.")
        case .httpStatus(429): String(localized: "Search1API keyless access is rate-limited. Please wait and try again.")
        case .httpStatus(let code): String(localized: "Search1API returned HTTP \(code).")
        }
    }
}
