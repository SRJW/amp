import Foundation

/// Serializes parsed lyrics into clean standard line-by-line `[mm:ss.xx]` LRC for file embedding.
enum LyricsFormatter {
    static func lineByLineLRC(from rawText: String, offsetMs: Int64 = 0) -> String {
        guard let parsed = LyricsParser.parse(rawText) else { return rawText.trimmed }
        switch parsed {
        case .plain(let lines):
            return lines.joined(separator: "\n").trimmed
        case .synced(let lines):
            return lines.map { line in
                let adjusted = max(line.timeMs + offsetMs, 0)
                return "\(formatTimestamp(adjusted))\(line.text)"
            }.joined(separator: "\n")
        }
    }

    static func formatTimestamp(_ ms: Int64) -> String {
        let clamped = max(ms, 0)
        let minutes = clamped / 60_000
        let seconds = (clamped % 60_000) / 1_000
        let centiseconds = (clamped % 1_000) / 10
        return String(format: "[%02lld:%02lld.%02lld]", minutes, seconds, centiseconds)
    }
}

/// Backup line-synced lyrics provider backed by NetEase Cloud Music's lyric catalog.
/// Queried only when LRCLIB has no synced match or is unavailable; always outputs clean line-by-line LRC.
actor NetEaseLyricsProvider: OnlineLyricsProvider {
    nonisolated let name = "NetEase"
    nonisolated let supportsSyncedLyrics = true

    private static let searchURL = URL(string: "https://music.163.com/api/search/get")!
    private static let lyricURL = URL(string: "https://music.163.com/api/song/lyric")!
    private let http: HTTPClient
    private let now: @Sendable () -> Int64
    private var blockedUntilMs: Int64 = 0

    init(http: HTTPClient = URLSessionHTTPClient(cachePolicy: .reloadIgnoringLocalCacheData, timeout: 8),
         now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.http = http
        self.now = now
    }

    func exact(_ query: LyricsQuery) async -> ProviderResponse<LyricsCandidate> { .notFound }

    func search(_ query: LyricsQuery, freeText: String?) async -> ProviderResponse<[LyricsCandidate]> {
        let term = freeText?.nonBlank ?? "\(query.title) \(query.artist)".trimmed
        guard !term.isBlank else { return .notFound }

        var searchComps = URLComponents(url: Self.searchURL, resolvingAgainstBaseURL: false)!
        searchComps.queryItems = [
            URLQueryItem(name: "s", value: term),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        guard let url = searchComps.url else { return .failed("invalid request") }
        let searchResp: ProviderResponse<SearchResponse> = await fetch(url)
        let songs: [SearchSong]
        switch searchResp {
        case .success(let payload): songs = payload.result?.songs ?? []
        case .notFound: return .notFound
        case .rateLimited(let at): return .rateLimited(retryAtMs: at)
        case .offline: return .offline
        case .failed(let reason): return .failed(reason)
        }

        var seen = Set<Int64>()
        var candidates: [LyricsCandidate] = songs.compactMap { s in
            guard s.id > 0, !s.name.isBlank, seen.insert(s.id).inserted else { return nil }
            let artistName = s.artists?.compactMap(\.name).filter { !$0.isBlank }.joined(separator: ", ") ?? ""
            guard !artistName.isBlank else { return nil }
            let durSec = s.duration.flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }
            return LyricsCandidate(
                provider: name,
                providerId: s.id,
                trackName: s.name,
                artistName: artistName,
                albumName: s.album?.name,
                durationSec: durSec
            )
        }

        if freeText?.nonBlank == nil {
            candidates = candidates.filter {
                let score = LyricsMatcher.score(query, $0)
                return !score.rejected && score.score >= LyricsMatcher.plausibleScore
            }.sorted { LyricsMatcher.score(query, $0).score > LyricsMatcher.score(query, $1).score }
        }

        var found: [LyricsCandidate] = []
        var failure: ProviderResponse<[LyricsCandidate]>?
        for var candidate in candidates.prefix(3) {
            guard !Task.isCancelled else { return .failed("cancelled") }
            var lyricComps = URLComponents(url: Self.lyricURL, resolvingAgainstBaseURL: false)!
            lyricComps.queryItems = [
                URLQueryItem(name: "id", value: String(candidate.providerId)),
                URLQueryItem(name: "lv", value: "1"),
                URLQueryItem(name: "tv", value: "-1"),
            ]
            guard let lyrURL = lyricComps.url else { continue }
            let resp: ProviderResponse<LyricResponse> = await fetch(lyrURL)
            switch resp {
            case .success(let payload):
                if payload.nolyric == true {
                    candidate.instrumental = true
                    found.append(candidate)
                    continue
                }
                guard let raw = payload.lrc?.lyric?.nonBlank else { continue }
                if let parsed = LyricsParser.parse(raw) {
                    switch parsed {
                    case .synced:
                        // Normalize cleanly to standard line-by-line LRC.
                        candidate.syncedLyrics = LyricsFormatter.lineByLineLRC(from: raw)
                        found.append(candidate)
                        if freeText?.nonBlank == nil, LyricsMatcher.score(query, candidate).confident {
                            return .success(found)
                        }
                    case .plain:
                        candidate.plainLyrics = raw
                        found.append(candidate)
                    }
                }
            case .notFound: break
            case .rateLimited(let at):
                return found.isEmpty ? .rateLimited(retryAtMs: at) : .success(found)
            case .offline: failure = .offline
            case .failed(let reason): failure = .failed(reason)
            }
        }
        return found.isEmpty ? (failure ?? .success([])) : .success(found)
    }

    private func fetch<T: Decodable & Sendable>(_ url: URL) async -> ProviderResponse<T> {
        guard !Task.isCancelled else { return .failed("cancelled") }
        guard now() >= blockedUntilMs else { return .rateLimited(retryAtMs: blockedUntilMs) }
        var headers = LyricsHTTP.headers
        headers["Referer"] = "https://music.163.com/"
        do {
            let (data, response) = try await http.get(url, headers: headers)
            switch response.statusCode {
            case 200..<300:
                do { return .success(try JSONDecoder().decode(T.self, from: data)) }
                catch { return .failed("malformed response") }
            case 404: return .notFound
            case 429:
                blockedUntilMs = now() + LyricsHTTP.retryAfterMs(response.value(forHTTPHeaderField: "Retry-After"), nowMs: now())
                return .rateLimited(retryAtMs: blockedUntilMs)
            default: return .failed("HTTP \(response.statusCode)")
            }
        } catch {
            return LyricsHTTP.failure(error)
        }
    }

    private struct SearchResponse: Decodable, Sendable {
        let result: SearchResult?
    }
    private struct SearchResult: Decodable, Sendable {
        let songs: [SearchSong]?
    }
    private struct SearchSong: Decodable, Sendable {
        struct Artist: Decodable, Sendable { let name: String? }
        struct Album: Decodable, Sendable { let name: String? }
        let id: Int64
        let name: String
        let duration: Int64?
        let artists: [Artist]?
        let album: Album?
    }
    private struct LyricResponse: Decodable, Sendable {
        struct LrcBlock: Decodable, Sendable { let lyric: String? }
        let nolyric: Bool?
        let lrc: LrcBlock?
    }
}
