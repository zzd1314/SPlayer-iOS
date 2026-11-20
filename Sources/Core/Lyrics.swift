import Foundation

/// 一行歌词（id 为排序后的序号）
struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let text: String
}

struct LyricResponse: Decodable {
    struct Lyrics: Decodable { let lyric: String? }
    let code: Int
    let lrc: Lyrics?
    let tlyric: Lyrics?
}

enum LRC {
    /// 解析 LRC 文本：支持 [mm:ss.xx] / [mm:ss.xxx] / [mm:ss:xx] 及一行多标签
    static func parse(_ raw: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]") else {
            return []
        }

        var parsed: [(time: TimeInterval, text: String)] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }

            let text = regex
                .stringByReplacingMatches(in: rawLine, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: rawLine),
                      let secondRange = Range(match.range(at: 2), in: rawLine),
                      let minutes = Double(rawLine[minuteRange]),
                      let seconds = Double(rawLine[secondRange])
                else { continue }

                var fraction = 0.0
                if let fractionRange = Range(match.range(at: 3), in: rawLine),
                   let value = Double(rawLine[fractionRange]) {
                    let digits = rawLine[fractionRange].count
                    fraction = value / pow(10, Double(digits))
                }

                parsed.append((minutes * 60 + seconds + fraction, text))
            }
        }

        parsed.sort { $0.time < $1.time }
        return parsed.enumerated().map { index, item in
            LyricLine(id: index, time: item.time, text: item.text)
        }
    }
}

extension NeteaseAPI {
    /// 获取并解析歌词（含翻译参数，暂只使用原文）
    func lyric(id: Int, cookie: String?) async throws -> [LyricLine] {
        let response: LyricResponse = try await get(
            "/lyric",
            query: ["id": String(id), "lv": "-1", "tv": "-1"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌词失败")
        }
        return LRC.parse(response.lrc?.lyric ?? "")
    }
}
