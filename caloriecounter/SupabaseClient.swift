//
//  SupabaseClient.swift
//  caloriecounter
//
//  Read-only fetcher for the `favorite_foods` table on Supabase.
//  No authentication: the publishable (anon) key is used directly,
//  and the table's RLS policy allows public SELECT.
//

import Foundation

// MARK: - Configuration

enum SupabaseConfig {
    static let url = URL(string: "https://hdhaahuresmzfyirjumj.supabase.co")!
    /// Publishable (anon) key – safe to embed in the client.
    static let publishableKey = "sb_publishable_FTWxVcwWfuU73grtqhZI6g_Lh1BPthF"
}

// MARK: - DTO

/// A predefined favourite food, served from Supabase.
struct FavoriteFood: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let calories: Int
    let serving: String
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case http(status: Int, body: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let s, let body): return "Server error (\(s)): \(body)"
        case .decoding(let m):       return "Couldn't read response: \(m)"
        }
    }
}

// MARK: - Service

enum SupabaseService {
    /// Fetches all predefined favourite foods, ordered by `sort_order` then name.
    static func fetchFavoriteFoods() async throws -> [FavoriteFood] {
        let url = SupabaseConfig.url
            .appending(path: "/rest/v1/favorite_foods")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "id,name,calories,serving"),
                URLQueryItem(name: "order",  value: "sort_order.asc,name.asc")
            ])

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.http(status: status, body: body)
        }

        do {
            return try JSONDecoder().decode([FavoriteFood].self, from: data)
        } catch {
            throw SupabaseError.decoding("\(error)")
        }
    }
}
