//
//  Copyright (c) 2020 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import PythonKit
import PythonSupport
@preconcurrency import WebKit

// https://github.com/pvieito/PythonKit/pull/30#issuecomment-751132191
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

func loadSymbol<T>(_ name: String) -> T {
    unsafeBitCast(dlsym(RTLD_DEFAULT, name), to: T.self)
}

let Py_IsInitialized: @convention(c) () -> Int32 = loadSymbol("Py_IsInitialized")

let chunkSize: Int64 = 10_485_760 // https://github.com/yt-dlp/yt-dlp/blob/720c309932ea6724223d0a6b7781a0e92a74262c/yt_dlp/extractor/youtube.py#L2552

struct NativeJavaScriptOutput {
    let standardOutput: String
    let standardError: String
}

enum NativeJavaScriptRunnerError: LocalizedError {
    case invalidResult
    case mainThreadExecution
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidResult:
            return "The native JavaScript runner returned an invalid result."
        case .mainThreadExecution:
            return "The native JavaScript runner must be called off the main thread."
        case .timedOut:
            return "The native JavaScript runner timed out."
        }
    }
}

enum NativeJavaScriptRunner {
    private static let timeout: TimeInterval = 30

    static func run(script: String) throws -> NativeJavaScriptOutput {
        guard !Thread.isMainThread else {
            throw NativeJavaScriptRunnerError.mainThreadExecution
        }

        let resultBox = NativeJavaScriptResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            NativeJavaScriptExecution(script: script, timeout: timeout).start { result in
                resultBox.set(result)
                semaphore.signal()
            }
        }

        guard semaphore.wait(timeout: .now() + timeout + 5) == .success,
              let result = resultBox.get() else {
            throw NativeJavaScriptRunnerError.timedOut
        }
        return try result.get()
    }
}

private final class NativeJavaScriptResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<NativeJavaScriptOutput, Error>?

    func set(_ result: Result<NativeJavaScriptOutput, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<NativeJavaScriptOutput, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

@MainActor
private final class NativeJavaScriptExecution: NSObject, WKNavigationDelegate {
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
    private var completion: ((Result<NativeJavaScriptOutput, Error>) -> Void)?
    private var keepAlive: NativeJavaScriptExecution?
    private var didStartJavaScript = false

    init(script: String, timeout: TimeInterval) {
        self.script = script
        self.timeout = timeout
        super.init()
    }

    func start(completion: @escaping (Result<NativeJavaScriptOutput, Error>) -> Void) {
        self.completion = completion
        keepAlive = self

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = self
        webView.loadHTMLString(
            "<!doctype html><html><head></head><body></body></html>",
            baseURL: URL(string: "https://www.youtube.com")
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(NativeJavaScriptRunnerError.timedOut))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didStartJavaScript else { return }
        didStartJavaScript = true
        let functionBody = Self.scriptPrefix + script + Self.scriptSuffix
        webView.callAsyncJavaScript(
            functionBody,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            self.finish(result.flatMap(Self.decode))
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<NativeJavaScriptOutput, Error>) {
        guard let completion else { return }
        self.completion = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        self.webView = nil
        keepAlive = nil
        completion(result)
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

public struct Info: Codable {
    public var id: String
    public var title: String
    public var formats: [Format]
    public var description: String?
    public var upload_date: String?
    public var uploader: String?
    public var uploader_id: String?
    public var uploader_url: String?
    public var channel_id: String?
    public var channel_url: String?
    public var duration: TimeInterval?
    public var view_count: Int?
    public var average_rating: Double?
    public var age_limit: Int?
    public var webpage_url: String?
    public var categories: [String]?
    public var tags: [String]?
    public var playable_in_embed: Bool?
    public var is_live: Bool?
    public var was_live: Bool?
    public var live_status: String?
    public var release_timestamp: Int?
    
    public struct Chapter: Codable {
        public var title: String?
        public var start_time: TimeInterval?
        public var end_time: TimeInterval?
    }
    
    public var chapters: [Chapter]?
    public var like_count: Int?
    public var channel: String?
    public var availability: String?
    public var __post_extractor: String?
    public var original_url: String?
    public var webpage_url_basename: String
    public var extractor: String?
    public var extractor_key: String?
    public var playlist: [String]?
    public var playlist_index: Int?
    public var thumbnail: String?
    public var display_id: String?
    public var fulltitle: String?
    public var duration_string: String?
    public var requested_subtitles: [String]?
    public var __has_drm: Bool?
    
    public var language: String?
    public var media_type: String?
    
    public var subtitles: Dictionary<String, [Ext]>
    public var url: String?
}

public extension Info {
    var safeTitle: String {
        String(title[..<(title.index(title.startIndex, offsetBy: 40, limitedBy: title.endIndex) ?? title.endIndex)])
            .replacingOccurrences(of: "/", with: "_")
    }
}

public struct Format: Codable {
    public var asr: Int?
    public var filesize: Int?
    public var format_id: String
    public var format_note: String?
    public var fps: Double?
    public var height: Int?
    public var quality: Double?
    public var tbr: Double?
    public var url: String
    public var width: Int?
    public var language: String?
    public var language_preference: Int?
    public var ext: String
    public var vcodec: String?
    public var acodec: String?
    public var dynamic_range: String?
    public var abr: Double?
    public var vbr: Double?
    
    public struct DownloaderOptions: Codable {
        public var http_chunk_size: Int
    }
    
    public var downloader_options: DownloaderOptions?
    public var container: String?
    public var `protocol`: String
    public var audio_ext: String
    public var video_ext: String
    public var format: String
    public var resolution: String?
    public var http_headers: [String: String]
}

public extension Format {
    var urlRequest: URLRequest? {
        guard let url = URL(string: url) else {
            return nil
        }
        var request = URLRequest(url: url)
        for (field, value) in http_headers {
            request.addValue(value, forHTTPHeaderField: field)
        }
        
        return request
    }
    
    var isAudioOnly: Bool { vcodec == "none" }
    
    var isVideoOnly: Bool { acodec == "none" }
}

public struct Ext: Codable {
    public var ext: String?
    public var url: String?
    public var name: String?
}

public let defaultOptions: PythonObject = [
    "format": "bestvideo,bestaudio[ext=m4a]/best",
    "nocheckcertificate": true,
    "verbose": false,
]

public enum YoutubeDLError: Error {
    case noPythonModule
    case canceled
    case missingPOToken
}

open class YoutubeDL: NSObject {
    private enum ExtractionMode: Equatable {
        case defaultClient
        case mweb(poToken: String)
    }

    public static var pythonModuleURL: URL = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("io.github.kewlbear.youtubedl-ios") else { fatalError() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        catch {
            fatalError(error.localizedDescription)
        }
        return directory.appendingPathComponent("yt_dlp")
    }()

    public var version: String?

    internal var pythonObject: PythonObject?

    internal var options: PythonObject?

    private var extractionMode: ExtractionMode?
    
    public override init() {
        super.init()
    }
    
    func loadPythonModule() async throws -> PythonObject {
        if Py_IsInitialized() == 0 {
            PythonSupport.initialize()
        }
        
        let moduleExists = FileManager.default.fileExists(
            atPath: Self.pythonModuleURL.path
        )

        guard moduleExists else {
            throw YoutubeDLError.noPythonModule
        }
        return try importPythonModule()
    }
    
    private func importPythonModule() throws -> PythonObject {
        let sys = try Python.attemptImport("sys")
        let builtins = try Python.attemptImport("builtins")
        builtins.__youtubedl_ios_run_javascript = nativeJavaScriptRunner.pythonObject
        if let pluginRoot = Bundle.module.resourceURL?.path,
           !(Array(sys.path) ?? []).contains(pluginRoot) {
            sys.path.insert(1, pluginRoot)
        }
        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
            injectFakePopen(handler: popenHandler)
            
            sys.path.insert(1, Self.pythonModuleURL.path)
        }
        
        let pythonModule = try Python.attemptImport("yt_dlp")
        version = String(pythonModule.version.__version__)
        return pythonModule
    }

    private lazy var nativeJavaScriptRunner = PythonFunction { arguments in
        guard let script = arguments.first.flatMap(String.init) else {
            throw NativeJavaScriptRunnerError.invalidResult
        }
        let output = try NativeJavaScriptRunner.run(script: script)
        return Python.tuple([output.standardOutput, output.standardError])
    }
    
    func injectFakePopen(handler: PythonFunction) {
        runSimpleString("""
            import errno
            import os
            
            class Pop:
                def __init__(self, *args, **kwargs):
                    print('Popen.__init__:', self, args)#, kwargs)
                    self.__args = args
            
                def communicate(self, *args, **kwargs):
                    print('Popen.communicate:', self, args, kwargs)
                    return self.handler(self, self.__args)

                def kill(self):
                    print('Popen.kill:', self)

                def wait(self, **kwargs):
                    print('Popen.wait:', self, kwargs)

                def __enter__(self):
                    return self
                
                def __exit__(self, type, value, traceback):
                    pass
            
            import subprocess
            subprocess.Popen = Pop
            """)
        
        let subprocess = Python.import("subprocess")
        subprocess.Popen.handler = handler.pythonObject
    }
    
    lazy var popenHandler = PythonFunction { args in
        print(#function, args)
        let popen = args[0]
        let result = Array<String?>(repeating: nil, count: 2)
        
        if let args: [String] = Array(args[1][0]) {
            popen.returncode = PythonObject(0)
            
            func read(pipe: Pipe) -> String? {
                let data = pipe.fileHandleForReading.availableData
                let output = String(data: data, encoding: .utf8)
                return output
            }
            
            return Python.tuple(result)
        }
        return Python.tuple(result)
    }
    
    func makePythonObject(_ options: PythonObject? = nil, initializePython: Bool = true) async throws -> PythonObject {
        let pythonModule = try await loadPythonModule()
        let options = options ?? defaultOptions
        pythonObject = pythonModule.YoutubeDL(options)
        self.options = options
        extractionMode = nil
        return pythonObject!
    }

    private func makeMWebPythonObject(poToken: String) async throws -> PythonObject {
        let playerClients: PythonObject = ["mweb".pythonObject]
        let poTokens: PythonObject = ["mweb.gvs+\(poToken)".pythonObject]
        let youtubeExtractorArgs: PythonObject = [
            "player_client": playerClients,
            "po_token": poTokens,
        ]
        let extractorArgs: PythonObject = [
            "youtube": youtubeExtractorArgs,
        ]
        let options: PythonObject = [
            "format": "bestvideo,bestaudio[ext=m4a]/best",
            "nocheckcertificate": true,
            "verbose": false,
            "extractor_args": extractorArgs,
        ]
        let object = try await makePythonObject(options)
        extractionMode = .mweb(poToken: poToken)
        return object
    }
    
    open func getInfo(url: URL) async throws -> (Info) {
        try await extractInfo(url: url, mode: .defaultClient)
    }

    open func getInfo(url: URL, mwebPOToken: String) async throws -> Info {
        guard !mwebPOToken.isEmpty else { throw YoutubeDLError.missingPOToken }
        return try await extractInfo(url: url, mode: .mweb(poToken: mwebPOToken))
    }

    private func extractInfo(url: URL, mode: ExtractionMode) async throws -> Info {
        let pythonObject: PythonObject
        if let _pythonObject = self.pythonObject,
           extractionMode == mode {
            pythonObject = _pythonObject
        } else {
            switch mode {
            case .defaultClient:
                pythonObject = try await makePythonObject()
                extractionMode = .defaultClient
            case .mweb(let poToken):
                pythonObject = try await makeMWebPythonObject(poToken: poToken)
            }
        }
        let decoder = PythonDecoder()
        let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
        return try decoder.decode(Info.self, from: info)
    }
    
    fileprivate static func validateDownloadResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    
    fileprivate static func movePythonModule(_ location: URL) throws {
        let directory = pythonModuleURL.deletingLastPathComponent()
        let backupURL = directory.appendingPathComponent("\(pythonModuleURL.lastPathComponent).backup")
        removeItem(at: backupURL)
        
        if FileManager.default.fileExists(atPath: pythonModuleURL.path) {
            try FileManager.default.moveItem(at: pythonModuleURL, to: backupURL)
        }
        
        do {
            try FileManager.default.moveItem(at: location, to: pythonModuleURL)
            removeItem(at: backupURL)
        } catch {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.moveItem(at: backupURL, to: pythonModuleURL)
            }
            throw error
        }
    }
    
    public static func downloadPythonModule(from url: URL, completionHandler: @escaping (Swift.Error?) -> Void) {
        Task {
            do {
                try await downloadPythonModule(from: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
    
    public static func downloadPythonModule(from url: URL) async throws {
        let stopWatch = StopWatch(); defer { stopWatch.report() }

        let (location, response) = try await URLSession.shared.download(from: url)
        try validateDownloadResponse(response)
        try movePythonModule(location)
    }
}

public func removeItem(at url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
//        print(#function, "removed", url.lastPathComponent)
    }
    catch {
        let error = error as NSError
        if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileNoSuchFile.rawValue {
            print(#function, error)
        }
    }
}

public class StopWatch {
    let t0 = Date()
    
    let name: String
    
    public init(name: String = #function) {
        self.name = name
        report(item: #function)
    }
    
    deinit {
//        report(item: #function)
    }
    
    public func report(item: String? = nil) {
        let now = Date()
        print(now, item ?? name, "took", now.timeIntervalSince(t0), "seconds")
    }
}
