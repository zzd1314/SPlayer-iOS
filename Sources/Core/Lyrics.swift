import Foundation

/// 逐字歌词中的一个词
struct LyricWord: Equatable {
    let time: TimeInterval
    let duration: TimeInterval
    let text: String
}

/// 一行歌词（id 为排序后的序号）
struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let text: String
    var translation: String? = nil
    /// 罗马音 / 音译
    var romanization: String? = nil
    /// 逐字时间轴（来自 YRC，可为空）
    var words: [LyricWord]? = nil
}

struct LyricBundle {
    let lines: [LyricLine]

    var hasTranslation: Bool {
        lines.contains { $0.translation?.isEmpty == false }
    }

    var hasRomanization: Bool {
        lines.contains { $0.romanization?.isEmpty == false }
    }

    var hasWordTiming: Bool {
        lines.contains { $0.words?.isEmpty == false }
    }
}

struct LyricResponse: Decodable {
    struct Lyrics: Decodable { let lyric: String? }
    let code: Int
    let lrc: Lyrics?
    let tlyric: Lyrics?
    let romalrc: Lyrics?
    let yrc: Lyrics?
}

enum LRC {
    private static let tagRegex = try? NSRegularExpression(
        pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]"
    )
    private static let yrcLineRegex = try? NSRegularExpression(
        pattern: "^\\[(\\d+),(\\d+)\\](.*)$"
    )
    private static let yrcWordRegex = try? NSRegularExpression(
        pattern: "\\((\\d+),(\\d+),-?\\d+\\)([^()]*)"
    )

    /// 解析 LRC 文本：支持 [mm:ss.xx] / [mm:ss.xxx] / [mm:ss:xx] 及一行多标签
    static func parse(_ raw: String) -> [LyricLine] {
        entries(raw).enumerated().map { index, item in
            LyricLine(id: index, time: item.time, text: item.text)
        }
    }

    /// 同时解析原文 / 翻译 / 罗马音 / 逐字时间轴，按时间就近合并
    static func parse(
        _ raw: String,
        translation rawTranslation: String?,
        romanization rawRomanization: String? = nil,
        yrc rawYRC: String? = nil
    ) -> LyricBundle {
        let wordsEntries = yrcEntries(rawYRC ?? "")

        let main: [(time: TimeInterval, text: String)]
        var wordsMap: [Int: [LyricWord]] = [:]
        if !wordsEntries.isEmpty {
            main = wordsEntries.map { ($0.time, $0.text) }
            for entry in wordsEntries {
                wordsMap[Int((entry.time * 100).rounded())] = entry.words
            }
        } else {
            main = LRC.entries(raw)
        }

        let translations = LRC.entries(rawTranslation ?? "")
        let romanizations = LRC.entries(rawRomanization ?? "")

        var translationMap: [Int: String] = [:]
        for item in translations {
            translationMap[Int((item.time * 100).rounded())] = item.text
        }
        var romanizationMap: [Int: String] = [:]
        for item in romanizations {
            romanizationMap[Int((item.time * 100).rounded())] = item.text
        }

        let lines = main.enumerated().map { index, item -> LyricLine in
            let key = Int((item.time * 100).rounded())
            return LyricLine(
                id: index,
                time: item.time,
                text: item.text,
                translation: nearby(translationMap, key: key),
                romanization: nearby(romanizationMap, key: key),
                words: wordsMap[key] ?? nearby(wordsMap, key: key)
            )
        }
        return LyricBundle(lines: lines)
    }

    /// 关键字 ±2 个百分秒内就近取值
    private static func nearby(_ map: [Int: String], key: Int) -> String? {
        map[key] ?? map[key - 1] ?? map[key + 1] ?? map[key - 2] ?? map[key + 2]
    }

    private static func nearby(_ map: [Int: [LyricWord]], key: Int) -> [LyricWord]? {
        map[key] ?? map[key - 1] ?? map[key + 1] ?? map[key - 2] ?? map[key + 2]
    }

    private static func entries(_ raw: String) -> [(time: TimeInterval, text: String)] {
        guard let regex = tagRegex else { return [] }
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
        return parsed
    }

    /// 解析 YRC 逐字歌词：`[start,duration](wordStart,wordDuration,0)词...`
    private static func yrcEntries(
        _ raw: String
    ) -> [(time: TimeInterval, text: String, words: [LyricWord])] {
        guard let lineRegex = yrcLineRegex, let wordRegex = yrcWordRegex else { return [] }
        var parsed: [(time: TimeInterval, text: String, words: [LyricWord])] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }

            let nsLine = line as NSString
            let lineRange = NSRange(location: 0, length: nsLine.length)
            guard let lineMatch = lineRegex.firstMatch(in: line, range: lineRange),
                  let startRange = Range(lineMatch.range(at: 1), in: line),
                  let bodyRange = Range(lineMatch.range(at: 3), in: line),
                  let start = Double(line[startRange])
            else { continue }

            let body = String(line[bodyRange])
            let nsBody = body as NSString
            let bodyRangeNS = NSRange(location: 0, length: nsBody.length)

            var words: [LyricWord] = []
            for match in wordRegex.matches(in: body, range: bodyRangeNS) {
                guard let wordStartRange = Range(match.range(at: 1), in: body),
                      let durationRange = Range(match.range(at: 2), in: body),
                      let wordTextRange = Range(match.range(at: 3), in: body),
                      let wordStart = Double(body[wordStartRange]),
                      let wordDuration = Double(body[durationRange])
                else { continue }
                words.append(
                    LyricWord(
                        time: wordStart / 1000,
                        duration: wordDuration / 1000,
                        text: String(body[wordTextRange])
                    )
                )
            }

            guard !words.isEmpty else { continue }
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            parsed.append((start / 1000, text, words))
        }

        parsed.sort { $0.time < $1.time }
        return parsed
    }
}

extension NeteaseAPI {
    /// 获取并解析歌词（逐字 / 原文 / 翻译 / 罗马音），优先使用 /lyric/new
    func lyricBundle(id: Int, cookie: String?) async throws -> LyricBundle {
        if let response: LyricResponse = try? await get(
            "/lyric/new",
            query: ["id": String(id), "cp": "false"],
            cookie: cookie
        ), response.code == 200 {
            let bundle = LRC.parse(
                response.lrc?.lyric ?? "",
                translation: response.tlyric?.lyric,
                romanization: response.romalrc?.lyric,
                yrc: response.yrc?.lyric
            )
            if !bundle.lines.isEmpty {
                return bundle
            }
        }

        let response: LyricResponse = try await get(
            "/lyric",
            query: ["id": String(id), "lv": "-1", "tv": "-1", "rv": "-1"],
            cookie: cookie
        )
        guard response.code == 200 else {
            throw APIError.business(code: response.code, message: "获取歌词失败")
        }
        return LRC.parse(
            response.lrc?.lyric ?? "",
            translation: response.tlyric?.lyric,
            romanization: response.romalrc?.lyric,
            yrc: response.yrc?.lyric
        )
    }
}
