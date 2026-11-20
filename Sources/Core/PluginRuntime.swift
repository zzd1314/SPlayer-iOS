import CryptoKit
import Foundation
import JavaScriptCore

// MARK: - 设置结构

/// `splayer.register({ settings: [...] })` 声明的单个设置项
struct PluginSetting: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case text
        case toggle
        case number
        case select
    }

    let key: String
    let kind: Kind
    let label: String
    let description: String?
    let defaultValue: PluginValue?
    let placeholder: String?
    let minValue: Double?
    let maxValue: Double?
    let options: [PluginSettingOption]

    var id: String { key }

    init?(dictionary: [String: Any]) {
        guard let key = dictionary["key"] as? String, !key.isEmpty else { return nil }

        switch (dictionary["type"] as? String ?? "text").lowercased() {
        case "switch", "toggle", "boolean", "bool":
            kind = .toggle
        case "number", "slider", "range":
            kind = .number
        case "select", "dropdown", "choice":
            kind = .select
        default:
            kind = .text
        }

        self.key = key
        label = dictionary["label"] as? String ?? key

        let rawDescription = (dictionary["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        description = rawDescription?.isEmpty == false ? rawDescription : nil
        defaultValue = PluginValue(any: dictionary["default"])
        placeholder = dictionary["placeholder"] as? String
        minValue = (dictionary["min"] as? NSNumber)?.doubleValue
        maxValue = (dictionary["max"] as? NSNumber)?.doubleValue
        options = (dictionary["options"] as? [[String: Any]] ?? []).compactMap { option in
            guard let label = option["label"] as? String else { return nil }
            return PluginSettingOption(label: label, value: PluginValue(any: option["value"]) ?? .string(label))
        }
    }
}

struct PluginSettingOption: Codable, Hashable, Identifiable {
    let label: String
    let value: PluginValue

    var id: String { label + "|" + value.displayText }
}

/// `splayer.register({ menus: [...] })` 声明的菜单项
struct PluginMenu: Codable, Hashable, Identifiable {
    let id: String
    let label: String
}

/// 插件运行后注册的信息
struct PluginRegistration {
    let settings: [PluginSetting]
    let menus: [PluginMenu]
    /// 插件声明的宿主音源能力，键为宿主音源标识（当前仅 wy）
    let sources: [String: PluginSource]
}

/// `splayer.register({ sources: { wy: { actions: [...] } } })` 声明的单个音源能力
struct PluginSource: Codable, Hashable {
    let name: String?
    let actions: [String]
    let qualities: [String]

    init?(dictionary: [String: Any]) {
        let rawActions = dictionary["actions"]
        if let list = rawActions as? [String] {
            actions = list
        } else if let map = rawActions as? [String: Any] {
            actions = Array(map.keys)
        } else {
            actions = []
        }
        qualities = (dictionary["qualities"] as? [String]) ?? []
        name = dictionary["name"] as? String
    }
}

// MARK: - JavaScript 运行时

/// 每个插件一个 JSContext，桥接 splayer API（storage / settings / request / 播放事件）
@MainActor
final class PluginRuntime {
    weak var manager: PluginManager?

    private var contexts: [String: JSContext] = [:]
    private var timers: [String: [Int: PluginTimer]] = [:]
    private var pendingHostCalls: [Int: HostCallWaiter] = [:]
    private var hostCallSequence = 0

    private struct PluginTimer {
        let timer: Timer
        let repeats: Bool
    }

    private struct HostCallWaiter {
        let pluginID: String
        let continuation: CheckedContinuation<Any?, Error>
        let timeoutTask: Task<Void, Never>
    }

    /// 加载（或重新加载）插件脚本
    func load(pluginID: String, script: String) {
        unload(pluginID: pluginID)
        guard let context = JSContext() else {
            manager?.setRuntimeError(pluginID: pluginID, message: "无法创建 JavaScript 运行环境")
            return
        }

        context.name = "SPlayerPlugin-\(pluginID)"
        context.exceptionHandler = { [weak self] _, exception in
            guard let exception else { return }
            let message = exception.toString() ?? "未知脚本错误"
            Task { @MainActor [weak self] in
                self?.manager?.setRuntimeError(pluginID: pluginID, message: message)
            }
        }

        installNativeBridge(in: context, pluginID: pluginID)

        context.evaluateScript(Self.bootstrapScript)
        if let exception = context.exception {
            manager?.setRuntimeError(
                pluginID: pluginID,
                message: exception.toString() ?? "插件运行时初始化失败"
            )
            context.exception = nil
            return
        }

        context.evaluateScript(script)
        if let exception = context.exception {
            manager?.setRuntimeError(
                pluginID: pluginID,
                message: exception.toString() ?? "插件脚本执行失败"
            )
            context.exception = nil
        } else {
            manager?.setRuntimeError(pluginID: pluginID, message: nil)
        }

        contexts[pluginID] = context
    }

    func unload(pluginID: String) {
        contexts.removeValue(forKey: pluginID)
        timers[pluginID]?.values.forEach { $0.timer.invalidate() }
        timers[pluginID] = nil

        let pending = pendingHostCalls.filter { $0.value.pluginID == pluginID }.map(\.key)
        for callID in pending {
            finishHostCall(callID: callID, result: .failure(PluginError.runtimeUnavailable))
        }
    }

    func isLoaded(pluginID: String) -> Bool {
        contexts[pluginID] != nil
    }

    // MARK: 音源钩子调用（Swift → JS）

    /// 调用插件注册的音源钩子（musicUrl / musicLyric / musicPic / musicSearch）
    func callSource(
        pluginID: String,
        action: String,
        payload: [String: Any],
        timeout: TimeInterval = 20
    ) async throws -> Any? {
        guard let context = contexts[pluginID] else { throw PluginError.runtimeUnavailable }

        hostCallSequence += 1
        let callID = hostCallSequence
        let payloadJSON = Self.encode(payload)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 1) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finishHostCall(
                    callID: callID,
                    result: .failure(PluginError.runtimeTimeout(action))
                )
            }
            pendingHostCalls[callID] = HostCallWaiter(
                pluginID: pluginID,
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            guard let function = context.objectForKeyedSubscript("__hostCall"),
                  !function.isUndefined,
                  !function.isNull else {
                finishHostCall(callID: callID, result: .failure(PluginError.runtimeUnavailable))
                return
            }

            _ = function.call(withArguments: [callID, action, payloadJSON])
            if let exception = context.exception {
                context.exception = nil
                finishHostCall(
                    callID: callID,
                    result: .failure(PluginError.runtimeCallFailed(exception.toString() ?? "插件脚本异常"))
                )
            }
        }
    }

    private func finishHostCall(callID: Int, result: Result<Any?, Error>) {
        guard let waiter = pendingHostCalls.removeValue(forKey: callID) else { return }
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(with: result)
    }

    // MARK: 事件分发

    func dispatchPlayerEvent(_ event: String, payload: [String: Any]) {
        guard !contexts.isEmpty else { return }
        let json = Self.encode(payload)
        for (pluginID, context) in contexts {
            invoke(context, function: "__dispatchPlayerEvent", arguments: [event, json], pluginID: pluginID)
        }
    }

    func dispatchSettingChange(pluginID: String, key: String, valueJSON: String) {
        guard let context = contexts[pluginID] else { return }
        invoke(context, function: "__dispatchSettingChange", arguments: [key, valueJSON], pluginID: pluginID)
    }

    private func invoke(_ context: JSContext, function name: String, arguments: [Any], pluginID: String) {
        guard let function = context.objectForKeyedSubscript(name),
              !function.isUndefined,
              !function.isNull else { return }
        _ = function.call(withArguments: arguments)
        if let exception = context.exception {
            manager?.handleLog(
                pluginID: pluginID,
                level: "error",
                message: exception.toString() ?? "插件事件处理出错"
            )
            context.exception = nil
        }
    }

    // MARK: 原生桥

    private func installNativeBridge(in context: JSContext, pluginID: String) {
        let registerBlock: @convention(block) (String) -> Void = { [weak self] json in
            MainActor.assumeIsolated {
                self?.handleRegister(pluginID: pluginID, json: json)
            }
        }

        let logBlock: @convention(block) (String, String) -> Void = { [weak self] level, message in
            MainActor.assumeIsolated {
                self?.manager?.handleLog(pluginID: pluginID, level: level, message: message)
            }
        }

        let storageGetBlock: @convention(block) (String) -> String = { [weak self] key in
            MainActor.assumeIsolated {
                self?.manager?.storageGet(pluginID: pluginID, key: key) ?? ""
            }
        }

        let storageSetBlock: @convention(block) (String, String) -> Void = { [weak self] key, value in
            MainActor.assumeIsolated {
                self?.manager?.storageSet(pluginID: pluginID, key: key, value: value)
            }
        }

        let storageRemoveBlock: @convention(block) (String) -> Void = { [weak self] key in
            MainActor.assumeIsolated {
                self?.manager?.storageRemove(pluginID: pluginID, key: key)
            }
        }

        let settingGetBlock: @convention(block) (String) -> String = { [weak self] key in
            MainActor.assumeIsolated {
                self?.manager?.settingValueJSON(pluginID: pluginID, key: key) ?? ""
            }
        }

        let nowBlock: @convention(block) () -> Double = { Date().timeIntervalSince1970 * 1000 }

        let versionBlock: @convention(block) () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        }

        let localeBlock: @convention(block) () -> String = { Locale.current.identifier }

        let requestBlock: @convention(block) (Double, String, String, String, String, String, Double) -> Void = {
            [weak self] requestID, url, method, headers, body, responseType, timeout in
            MainActor.assumeIsolated {
                self?.performRequest(
                    pluginID: pluginID,
                    requestID: Int(requestID),
                    url: url,
                    method: method,
                    headersJSON: headers,
                    body: body,
                    responseType: responseType,
                    timeout: timeout
                )
            }
        }

        let setTimeoutBlock: @convention(block) (Double, Double) -> Void = { [weak self] timerID, delay in
            MainActor.assumeIsolated {
                self?.scheduleTimer(pluginID: pluginID, timerID: Int(timerID), delay: delay, repeats: false)
            }
        }

        let setIntervalBlock: @convention(block) (Double, Double) -> Void = { [weak self] timerID, delay in
            MainActor.assumeIsolated {
                self?.scheduleTimer(pluginID: pluginID, timerID: Int(timerID), delay: delay, repeats: true)
            }
        }

        let clearTimerBlock: @convention(block) (Double) -> Void = { [weak self] timerID in
            MainActor.assumeIsolated {
                self?.clearTimer(pluginID: pluginID, timerID: Int(timerID))
            }
        }

        let cryptoBlock: @convention(block) (String, String, String) -> String = { algorithm, input, key in
            Self.digest(algorithm: algorithm, input: input, key: key)
        }

        let hostResolveBlock: @convention(block) (Double, Bool, String, String) -> Void = {
            [weak self] callID, ok, json, errorText in
            MainActor.assumeIsolated {
                let result: Result<Any?, Error>
                if ok {
                    result = .success(Self.decode(json))
                } else {
                    result = .failure(PluginError.runtimeCallFailed(errorText.isEmpty ? "插件脚本异常" : errorText))
                }
                self?.finishHostCall(callID: Int(callID), result: result)
            }
        }

        context.setObject(registerBlock, forKeyedSubscript: "__nativeRegister" as NSString)
        context.setObject(logBlock, forKeyedSubscript: "__nativeLog" as NSString)
        context.setObject(storageGetBlock, forKeyedSubscript: "__nativeStorageGet" as NSString)
        context.setObject(storageSetBlock, forKeyedSubscript: "__nativeStorageSet" as NSString)
        context.setObject(storageRemoveBlock, forKeyedSubscript: "__nativeStorageRemove" as NSString)
        context.setObject(settingGetBlock, forKeyedSubscript: "__nativeSettingGet" as NSString)
        context.setObject(nowBlock, forKeyedSubscript: "__nativeNow" as NSString)
        context.setObject(versionBlock, forKeyedSubscript: "__nativeVersion" as NSString)
        context.setObject(localeBlock, forKeyedSubscript: "__nativeLocale" as NSString)
        context.setObject(requestBlock, forKeyedSubscript: "__nativeRequest" as NSString)
        context.setObject(setTimeoutBlock, forKeyedSubscript: "__nativeSetTimeout" as NSString)
        context.setObject(setIntervalBlock, forKeyedSubscript: "__nativeSetInterval" as NSString)
        context.setObject(clearTimerBlock, forKeyedSubscript: "__nativeClearTimer" as NSString)
        context.setObject(cryptoBlock, forKeyedSubscript: "__nativeCrypto" as NSString)
        context.setObject(hostResolveBlock, forKeyedSubscript: "__nativeHostResolve" as NSString)
    }

    private func handleRegister(pluginID: String, json: String) {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let settings = (object["settings"] as? [[String: Any]] ?? []).compactMap(PluginSetting.init(dictionary:))
        let menus = (object["menus"] as? [[String: Any]] ?? []).compactMap { item -> PluginMenu? in
            guard let id = item["id"] as? String, let label = item["label"] as? String else { return nil }
            return PluginMenu(id: id, label: label)
        }
        let sources = (object["sources"] as? [String: Any] ?? [:])
            .compactMapValues { PluginSource(dictionary: $0) }
        manager?.applyRegistration(pluginID: pluginID, settings: settings, menus: menus, sources: sources)
    }

    // MARK: 定时器

    private func scheduleTimer(pluginID: String, timerID: Int, delay: Double, repeats: Bool) {
        clearTimer(pluginID: pluginID, timerID: timerID)

        let interval = max(repeats ? 0.01 : 0, delay / 1000)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fireTimer(pluginID: pluginID, timerID: timerID)
            }
        }
        timers[pluginID, default: [:]][timerID] = PluginTimer(timer: timer, repeats: repeats)
    }

    private func clearTimer(pluginID: String, timerID: Int) {
        timers[pluginID]?[timerID]?.timer.invalidate()
        timers[pluginID]?[timerID] = nil
    }

    private func fireTimer(pluginID: String, timerID: Int) {
        guard let entry = timers[pluginID]?[timerID] else { return }
        if !entry.repeats {
            entry.timer.invalidate()
            timers[pluginID]?[timerID] = nil
        }

        guard let context = contexts[pluginID],
              let function = context.objectForKeyedSubscript("__fireTimer"),
              !function.isUndefined else { return }

        _ = function.call(withArguments: [timerID])
        if let exception = context.exception {
            manager?.handleLog(
                pluginID: pluginID,
                level: "error",
                message: exception.toString() ?? "定时器回调出错"
            )
            context.exception = nil
        }
    }

    // MARK: 网络请求

    private func performRequest(
        pluginID: String,
        requestID: Int,
        url urlString: String,
        method: String,
        headersJSON: String,
        body: String,
        responseType: String,
        timeout: Double
    ) {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            resolve(
                pluginID: pluginID,
                requestID: requestID,
                success: false,
                status: 0,
                headersJSON: "{}",
                body: "",
                error: "仅支持 http/https 请求"
            )
            return
        }

        var request = URLRequest(url: url)
        let upperMethod = method.isEmpty ? "GET" : method.uppercased()
        request.httpMethod = upperMethod
        request.timeoutInterval = min(max(5, timeout / 1000), 120)

        if let data = headersJSON.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if !body.isEmpty, upperMethod != "GET", upperMethod != "HEAD" {
            request.httpBody = body.data(using: .utf8)
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let httpResponse = response as? HTTPURLResponse

            var headers: [String: String] = [:]
            httpResponse?.allHeaderFields.forEach { key, value in
                if let key = key as? String {
                    headers[key] = String(describing: value)
                }
            }
            let headersText: String
            if let data = try? JSONSerialization.data(withJSONObject: headers),
               let text = String(data: data, encoding: .utf8) {
                headersText = text
            } else {
                headersText = "{}"
            }

            let status = httpResponse?.statusCode ?? 0
            let payload: String
            if responseType == "arraybuffer" {
                payload = (data ?? Data()).base64EncodedString()
            } else {
                payload = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            }

            let errorText = error?.localizedDescription ?? ""
            Task { @MainActor [weak self] in
                self?.resolve(
                    pluginID: pluginID,
                    requestID: requestID,
                    success: error == nil,
                    status: status,
                    headersJSON: headersText,
                    body: payload,
                    error: errorText
                )
            }
        }.resume()
    }

    private func resolve(
        pluginID: String,
        requestID: Int,
        success: Bool,
        status: Int,
        headersJSON: String,
        body: String,
        error: String
    ) {
        guard let context = contexts[pluginID],
              let function = context.objectForKeyedSubscript("__resolveRequest"),
              !function.isUndefined else { return }

        _ = function.call(withArguments: [requestID, success, status, headersJSON, body, error])
        if let exception = context.exception {
            manager?.handleLog(
                pluginID: pluginID,
                level: "error",
                message: exception.toString() ?? "网络回调处理出错"
            )
            context.exception = nil
        }
    }

    static func encode(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }

    private static func decode(_ json: String) -> Any? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    // MARK: 摘要工具

    nonisolated private static func digest(algorithm: String, input: String, key: String) -> String {
        let data = Data(input.utf8)

        switch algorithm.lowercased() {
        case "md5":
            return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha1":
            return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "sha256":
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case "hmac-sha1":
            let code = HMAC<Insecure.SHA1>.authenticationCode(
                for: data,
                using: SymmetricKey(data: Data(key.utf8))
            )
            return Data(code).map { String(format: "%02x", $0) }.joined()
        case "hmac-sha256":
            let code = HMAC<SHA256>.authenticationCode(
                for: data,
                using: SymmetricKey(data: Data(key.utf8))
            )
            return Data(code).map { String(format: "%02x", $0) }.joined()
        case "base64":
            return data.base64EncodedString()
        case "base64-decode":
            return Data(base64Encoded: input).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        default:
            return ""
        }
    }

    // MARK: JS 桥接脚本

    private static let bootstrapScript = #"""
    (function (global) {
      if (global.__splayerRuntimeReady) { return; }
      global.__splayerRuntimeReady = true;

      var listeners = {};

      function addListener(kind, event, callback) {
        if (typeof callback !== "function") { return; }
        var key = kind + ":" + String(event);
        (listeners[key] || (listeners[key] = [])).push(callback);
      }

      function emit(kind, event, payload) {
        var callbacks = listeners[kind + ":" + String(event)];
        if (!callbacks || !callbacks.length) { return; }
        callbacks.slice().forEach(function (callback) {
          try {
            var result = callback(payload);
            if (result && typeof result.catch === "function") {
              result.catch(function (error) { reportError(error); });
            }
          } catch (error) {
            reportError(error);
          }
        });
      }

      function reportError(error) {
        try {
          __nativeLog("error", String(error && error.stack ? error.stack : error));
        } catch (ignored) {}
      }

      var timerCallbacks = {};
      var timerSequence = 0;

      global.setTimeout = function (callback, delay) {
        if (typeof callback !== "function") { return 0; }
        var id = ++timerSequence;
        timerCallbacks[id] = callback;
        try { __nativeSetTimeout(id, Number(delay) || 0); } catch (error) { reportError(error); }
        return id;
      };

      global.setInterval = function (callback, delay) {
        if (typeof callback !== "function") { return 0; }
        var id = ++timerSequence;
        timerCallbacks[id] = callback;
        try { __nativeSetInterval(id, Number(delay) || 0); } catch (error) { reportError(error); }
        return id;
      };

      global.clearTimeout = function (id) {
        delete timerCallbacks[id];
        try { __nativeClearTimer(Number(id) || 0); } catch (error) {}
      };

      global.clearInterval = global.clearTimeout;

      global.__fireTimer = function (id) {
        var callback = timerCallbacks[id];
        if (typeof callback !== "function") { return; }
        try {
          callback();
        } catch (error) {
          reportError(error);
        }
      };

      global.console = {
        log: function () { __nativeLog("info", Array.prototype.map.call(arguments, formatLog).join(" ")); },
        info: function () { __nativeLog("info", Array.prototype.map.call(arguments, formatLog).join(" ")); },
        warn: function () { __nativeLog("warn", Array.prototype.map.call(arguments, formatLog).join(" ")); },
        error: function () { __nativeLog("error", Array.prototype.map.call(arguments, formatLog).join(" ")); },
        debug: function () { __nativeLog("debug", Array.prototype.map.call(arguments, formatLog).join(" ")); }
      };

      function formatLog(value) {
        if (typeof value === "string") { return value; }
        if (value instanceof Error) { return String(value.stack || value); }
        try { return JSON.stringify(value); } catch (error) { return String(value); }
      }

      function parseJSON(text) {
        try { return JSON.parse(text); } catch (error) { return undefined; }
      }

      function nativeDigest(algorithm, input, key) {
        try {
          return __nativeCrypto(String(algorithm), String(input), key === undefined || key === null ? "" : String(key));
        } catch (error) {
          return "";
        }
      }

      function base64ToBytes(base64) {
        var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var clean = String(base64 || "").replace(/[^A-Za-z0-9+/=]/g, "");
        var bytes = [];
        var buffer = 0;
        var bits = 0;
        for (var i = 0; i < clean.length; i += 1) {
          var character = clean.charAt(i);
          if (character === "=") { break; }
          var value = alphabet.indexOf(character);
          if (value < 0) { continue; }
          buffer = (buffer << 6) | value;
          bits += 6;
          if (bits >= 8) {
            bits -= 8;
            bytes.push((buffer >> bits) & 0xFF);
          }
        }
        return new Uint8Array(bytes);
      }

      global.__dispatchPlayerEvent = function (event, json) {
        emit("player", event, json ? parseJSON(json) : null);
      };

      global.__dispatchEvent = function (event, json) {
        emit("app", event, json ? parseJSON(json) : null);
      };

      global.__dispatchSettingChange = function (key, valueJson) {
        emit("setting", key, valueJson ? parseJSON(valueJson) : null);
      };

      global.__hostCall = function (id, action, payloadJson) {
        var payload = payloadJson ? parseJSON(payloadJson) : null;
        var callbacks = listeners["app:" + String(action)] || [];
        var handler = callbacks.length ? callbacks[callbacks.length - 1] : null;
        if (typeof handler !== "function") {
          __nativeHostResolve(id, false, "", "插件未实现 " + action);
          return;
        }

        var value;
        try {
          value = handler(payload);
        } catch (error) {
          __nativeHostResolve(id, false, "", String(error && error.message ? error.message : error));
          return;
        }

        Promise.resolve(value).then(function (result) {
          var json = "null";
          try {
            json = JSON.stringify(result === undefined ? null : result);
          } catch (error) {
            json = "null";
          }
          __nativeHostResolve(id, true, json, "");
        }, function (error) {
          __nativeHostResolve(id, false, "", String(error && error.message ? error.message : error));
        });
      };

      var pendingRequests = {};
      var requestSequence = 0;

      global.__resolveRequest = function (id, ok, status, headersJson, body, errorText) {
        var entry = pendingRequests[id];
        if (!entry) { return; }
        delete pendingRequests[id];

        if (!ok) {
          entry.reject(new Error(errorText || "网络请求失败"));
          return;
        }

        var headers = parseJSON(headersJson) || {};
        var parsed = body;
        if (entry.responseType === "json") {
          var decoded = parseJSON(body);
          parsed = decoded === undefined ? body : decoded;
        } else if (entry.responseType === "arraybuffer") {
          parsed = base64ToBytes(body || "");
        }

        entry.resolve({ status: status, headers: headers, body: parsed });
      };

      function request(url, options) {
        options = options || {};
        return new Promise(function (resolve, reject) {
          var id = ++requestSequence;
          var responseType = options.responseType || "text";
          pendingRequests[id] = { resolve: resolve, reject: reject, responseType: responseType };

          var headers = {};
          if (options.headers) {
            Object.keys(options.headers).forEach(function (key) {
              headers[key] = String(options.headers[key]);
            });
          }

          var body = options.body;
          if (body !== undefined && body !== null && typeof body !== "string") {
            try { body = JSON.stringify(body); } catch (error) { body = String(body); }
          }

          try {
            __nativeRequest(
              id,
              String(url),
              String(options.method || "GET"),
              JSON.stringify(headers),
              body === undefined || body === null ? "" : String(body),
              responseType,
              Number(options.timeout || 20000)
            );
          } catch (error) {
            delete pendingRequests[id];
            reject(error);
          }
        });
      }

      var api = {
        version: __nativeVersion(),
        locale: __nativeLocale(),
        register: function (options) {
          options = options || {};
          var eventNames = [];
          if (Array.isArray(options.events)) {
            eventNames = options.events.map(String);
          } else if (options.events && typeof options.events === "object") {
            eventNames = Object.keys(options.events);
            eventNames.forEach(function (name) {
              if (typeof options.events[name] === "function") {
                addListener("app", name, options.events[name]);
              }
            });
          }

          var payload = {
            settings: Array.isArray(options.settings) ? options.settings : [],
            menus: Array.isArray(options.menus) ? options.menus : [],
            events: eventNames,
            sources: options.sources && typeof options.sources === "object" ? options.sources : {}
          };

          try {
            __nativeRegister(JSON.stringify(payload));
          } catch (error) {
            reportError(error);
          }
          return api;
        },
        player: {
          on: function (event, callback) {
            addListener("player", event, callback);
            return api.player;
          }
        },
        on: function (event, callback) {
          addListener("app", event, callback);
          return api;
        },
        request: request,
        storage: {
          get: function (key, fallback) {
            try {
              var raw = __nativeStorageGet(String(key));
              if (raw === null || raw === undefined || raw === "") {
                return fallback === undefined ? null : fallback;
              }
              var value = JSON.parse(raw);
              return value === null && fallback !== undefined ? fallback : value;
            } catch (error) {
              return fallback === undefined ? null : fallback;
            }
          },
          set: function (key, value) {
            try {
              __nativeStorageSet(String(key), JSON.stringify(value === undefined ? null : value));
              return true;
            } catch (error) {
              return false;
            }
          },
          remove: function (key) {
            try { __nativeStorageRemove(String(key)); } catch (error) {}
          }
        },
        getSetting: function (key, fallback) {
          try {
            var raw = __nativeSettingGet(String(key));
            if (raw === null || raw === undefined || raw === "") {
              return fallback === undefined ? null : fallback;
            }
            return JSON.parse(raw);
          } catch (error) {
            return fallback === undefined ? null : fallback;
          }
        },
        onSettingChange: function (key, callback) {
          addListener("setting", String(key), callback);
          return api;
        },
        log: {
          info: function () {
            __nativeLog("info", Array.prototype.map.call(arguments, formatLog).join(" "));
          },
          warn: function () {
            __nativeLog("warn", Array.prototype.map.call(arguments, formatLog).join(" "));
          },
          debug: function () {
            __nativeLog("debug", Array.prototype.map.call(arguments, formatLog).join(" "));
          },
          error: function () {
            __nativeLog("error", Array.prototype.map.call(arguments, formatLog).join(" "));
          }
        },
        now: function () {
          return __nativeNow();
        }
      };

      var cryptoAPI = {
        md5: function (input) { return nativeDigest("md5", input, ""); },
        sha1: function (input) { return nativeDigest("sha1", input, ""); },
        sha256: function (input) { return nativeDigest("sha256", input, ""); },
        hmacSha1: function (input, key) { return nativeDigest("hmac-sha1", input, key); },
        hmacSha256: function (input, key) { return nativeDigest("hmac-sha256", input, key); },
        base64Encode: function (input) { return nativeDigest("base64", input, ""); },
        base64Decode: function (input) { return nativeDigest("base64-decode", input, ""); }
      };

      api.utils = { crypto: cryptoAPI };
      api.crypto = cryptoAPI;

      global.splayer = api;
    })(this);
    """#
}
