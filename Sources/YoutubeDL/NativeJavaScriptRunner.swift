import Foundation
@preconcurrency import WebKit

struct NativeJavaScriptOutput {
    let standardOutput: String
    let standardError: String
}

enum NativeJavaScriptRunnerError: LocalizedError {
    case invalidResult
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidResult:
            return "The native JavaScript runner returned an invalid result."
        case .timedOut:
            return "The native JavaScript runner timed out."
        }
    }
}

enum NativeJavaScriptRunner {
    private static let timeout: TimeInterval = 60

    static func run(script: String) throws -> NativeJavaScriptOutput {
        let execute = {
            MainActor.assumeIsolated {
                NativeJavaScriptExecution(script: script, timeout: timeout).run()
            }
        }

        let result: Result<NativeJavaScriptOutput, Error>
        if Thread.isMainThread {
            result = execute()
        } else {
            result = DispatchQueue.main.sync(execute: execute)
        }
        return try result.get()
    }
}

@MainActor
private final class NativeJavaScriptExecution {
    private static let scriptPrefix = #"""
const __transgullLogs = [];
const communicate = async () => {
    throw new Error('Native iOS JavaScript communication is unavailable');
};
Object.entries({
    trace: 0,
    debug: 1,
    log: 2,
    info: 2,
    warn: 3,
    assert: 4,
    error: 5,
}).forEach(([fn, logType]) => {
    console[fn] = function() {
        __transgullLogs.push({logType, argsArr: Array.from(arguments)});
    };
});
return await (async () => {
"""#

    private static let scriptSuffix = #"""

})().then(
    () => ({logs: __transgullLogs}),
    error => ({
        logs: __transgullLogs,
        exception: String(error),
        stack: String(error?.stack ?? ''),
    })
);
"""#

    private let script: String
    private let timeout: TimeInterval
    private var webView: WKWebView?
    private var result: Result<NativeJavaScriptOutput, Error>?

    init(script: String, timeout: TimeInterval) {
        self.script = script
        self.timeout = timeout
    }

    func run() -> Result<NativeJavaScriptOutput, Error> {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        let functionBody = Self.scriptPrefix + script + Self.scriptSuffix

        webView.callAsyncJavaScript(
            functionBody,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            self.result = result.flatMap(Self.decode)
        }

        let deadline = Date(timeIntervalSinceNow: timeout)
        while result == nil, Date() < deadline {
            _ = RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }

        webView.stopLoading()
        self.webView = nil
        return result ?? .failure(NativeJavaScriptRunnerError.timedOut)
    }

    private static func decode(_ value: Any) -> Result<NativeJavaScriptOutput, Error> {
        guard let payload = value as? [String: Any],
              let logs = payload["logs"] as? [[String: Any]] else {
            return .failure(NativeJavaScriptRunnerError.invalidResult)
        }

        var standardOutput = ""
        var standardError = ""
        for log in logs {
            guard let logType = (log["logType"] as? NSNumber)?.intValue,
                  let arguments = log["argsArr"] as? [Any] else {
                continue
            }
            let line = arguments.map(render).joined(separator: " ") + "\n"
            if logType == 2 {
                standardOutput += line
            } else if logType == 5 {
                standardError += line
            }
        }

        if let exception = payload["exception"] as? String, !exception.isEmpty {
            standardError += exception + "\n"
            if let stack = payload["stack"] as? String, !stack.isEmpty {
                standardError += stack + "\n"
            }
        }

        return .success(NativeJavaScriptOutput(
            standardOutput: standardOutput,
            standardError: standardError
        ))
    }

    private static func render(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return string
        }
        if let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .withoutEscapingSlashes]
        ), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
