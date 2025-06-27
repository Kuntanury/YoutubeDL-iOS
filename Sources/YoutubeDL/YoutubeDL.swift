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
import Dispatch
//import UIKit
//import FFmpegSupport

// https://github.com/pvieito/PythonKit/pull/30#issuecomment-751132191
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

func loadSymbol<T>(_ name: String) -> T {
    unsafeBitCast(dlsym(RTLD_DEFAULT, name), to: T.self)
}

let Py_IsInitialized: @convention(c) () -> Int32 = loadSymbol("Py_IsInitialized")
let chunkSize: Int64 = 10_485_760 // https://github.com/yt-dlp/yt-dlp/blob/720c309932ea6724223d0a6b7781a0e92a74262c/yt_dlp/extractor/youtube.py#L2552

public let defaultOptions: PythonObject = [
    "format": "bestvideo,bestaudio[ext=m4a]/best",
    "nocheckcertificate": true,
    "verbose": false,
]

public enum YoutubeDLError: Error {
    case noPythonModule
    case canceled
    case notInitialized
}

//open class YoutubeDL: NSObject {
//    public struct Options: OptionSet, Codable {
//        public let rawValue: Int
//        
//        public static let noRemux       = Options(rawValue: 1 << 0)
//        public static let noTranscode   = Options(rawValue: 1 << 1)
//        public static let chunked       = Options(rawValue: 1 << 2)
//        public static let background    = Options(rawValue: 1 << 3)
//
//        public static let all: Options = [.noRemux, .noTranscode, .chunked, .background]
//        
//        public init(rawValue: Int) {
//            self.rawValue = rawValue
//        }
//    }
//    
//    public static let latestDownloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
//    
//    public static var pythonModuleURL: URL = {
//        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
//                .appendingPathComponent("io.github.kewlbear.youtubedl-ios") else { fatalError() }
//        do {
//            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
//        }
//        catch {
//            fatalError(error.localizedDescription)
//        }
//        return directory.appendingPathComponent("yt_dlp")
//    }()
//    
//    public var version: String?
//    
//    internal var pythonObject: PythonObject?
//
//    internal var options: PythonObject?
// 
//    public static let shared = YoutubeDL()
//    private let pythonQueue = DispatchQueue(label: "com.youtube-dl.python", qos: .userInitiated)
//    
//    public override init() {
//        super.init()
//        if Py_IsInitialized() == 0 {
//            PythonSupport.initialize()
//        }
//        
//        do {
//            let sys = try Python.attemptImport("sys")
//            if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
//                sys.path.insert(1, Self.pythonModuleURL.path)
//            }
//        } catch {
//            
//        }
//    }
//    
//    public func prepare(downloadIfNeeded: Bool = true) async throws {
//        if pythonObject == nil {
//            pythonObject = try await makePythonObject()
//        }
//    }
//    
//    func makePythonObject(_ options: PythonObject? = nil, initializePython: Bool = true) async throws -> PythonObject {
//        let pythonModule = try await loadPythonModule()
//        let options = options ?? defaultOptions
//        pythonObject = pythonModule.YoutubeDL(options)
//        self.options = options
//        return pythonObject!
//    }
//    
//    func loadPythonModule(downloadPythonModule: Bool = true) async throws -> PythonObject {
//        if Py_IsInitialized() == 0 {
//            PythonSupport.initialize()
//        }
//        
//        if !FileManager.default.fileExists(atPath: Self.pythonModuleURL.path) {
//            guard downloadPythonModule else {
//                throw YoutubeDLError.noPythonModule
//            }
//            try await Self.downloadPythonModule()
//        }
//        
//        let sys = try Python.attemptImport("sys")
//        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
//            //                injectFakePopen(handler: popenHandler)
//            
//            sys.path.insert(1, Self.pythonModuleURL.path)
//        }
//        
//        
//        let pythonModule = try Python.attemptImport("yt_dlp")
//        version = String(pythonModule.version.__version__)
//        return pythonModule
//    }
//    
//    open func getInfo(url: URL) async throws -> (Info) {
//            try await withCheckedThrowingContinuation { continuation in
//                pythonQueue.async {
//                    do {
//                        
//                        guard let pythonObject = self.pythonObject else {
//                            throw NSError(domain: "YTDLPKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Extractor not initialized"])
//                        }
//                        let decoder = PythonDecoder()
//                        let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: ["": url.absoluteString, "download": false, "process": true])
//                        continuation.resume(returning: (try decoder.decode(Info.self, from: info)))
//                    } catch {
//                        continuation.resume(throwing: error)
//                    }
//                }
//            }
//    }
//        
//    fileprivate static func movePythonModule(_ location: URL) throws {
//        do {
//            try FileManager.default.removeItem(at: pythonModuleURL)
//        }
//        catch {
//            let error = error as NSError
//            if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileNoSuchFile.rawValue {
//                print(#function, error)
//            }
//        }
//        
//        try FileManager.default.moveItem(at: location, to: pythonModuleURL)
//    }
//    
//    public static func downloadPythonModule(from url: URL = latestDownloadURL, completionHandler: @escaping (Swift.Error?) -> Void) {
//        let task = URLSession.shared.downloadTask(with: url) { (location, response, error) in
//            guard let location = location else {
//                completionHandler(error)
//                return
//            }
//            do {
//                try movePythonModule(location)
//
//                completionHandler(nil)
//            }
//            catch {
//                print(#function, error)
//                completionHandler(error)
//            }
//        }
//        
//        task.resume()
//    }
//    
//    public static func downloadPythonModule(from url: URL = latestDownloadURL) async throws {
//        let stopWatch = StopWatch(); defer { stopWatch.report() }
//        if #available(iOS 15.0, *) {
//            let (location, _) = try await URLSession.shared.download(from: url)
//            try movePythonModule(location)
//        } else {
//            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
//                downloadPythonModule(from: url) { error in
//                    if let error = error {
//                        continuation.resume(throwing: error)
//                    } else {
//                        continuation.resume()
//                    }
//                }
//            }
//        }
//    }
//}

extension URLSessionDownloadTask {
    var info: String {
        "\(taskDescription ?? "no task description") \(originalRequest?.value(forHTTPHeaderField: "Range") ?? "no range")"
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

/// Models
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

public extension Format {
    var isRemuxingNeeded: Bool { isVideoOnly || isAudioOnly }
    
    var isTranscodingNeeded: Bool {
        self.ext == "mp4"
            ? (self.vcodec ?? "").hasPrefix("av01.")
            : self.ext != "m4a"
    }
}



// 1. 扩展DispatchQueue使其符合SerialExecutor
extension DispatchQueue {
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

extension DispatchQueue: SerialExecutor {
    public func enqueue(_ job: UnownedJob) {
        async {
            job._runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
}

// 2. 实现GlobalActor
@globalActor
public struct PythonGlobalActor {
    public final class Actor: SerialExecutor {
        public let queue: DispatchQueue
        
        public init(queue: DispatchQueue) {
            self.queue = queue
        }
        
        public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
            queue.asUnownedSerialExecutor()
        }
        
        public func enqueue(_ job: UnownedJob) {
            queue.enqueue(job)
        }
    }
    
    public actor ActorType {
        private let executor: Actor
        
        public init(executor: Actor) {
            self.executor = executor
        }
        
        nonisolated public var unownedExecutor: UnownedSerialExecutor {
            executor.asUnownedSerialExecutor()
        }
    }
    
    public static let shared = ActorType(
        executor: Actor(queue: DispatchQueue(
            label: "com.youtube-dl.python",
            qos: .userInitiated
        ))
    )
}

// 3. 使用示例
@PythonGlobalActor
public final class YoutubeDL {
    
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
    
    public static let latestDownloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    
    private var isPrepared = false

    private var pythonObject: PythonObject?
    
    
    
    public nonisolated init() {
        if Py_IsInitialized() == 0 {
            PythonSupport.initialize()
            
            // 同步等待初始化完成
            let semaphore = DispatchSemaphore(value: 0)
            
            Task { @PythonGlobalActor in
                defer { semaphore.signal() }
                self.injectFakePopen()
            }
            
            semaphore.wait()
        }
    }
    
    private func prepare() async throws {
        
        if isPrepared { return }

        let sys = try Python.attemptImport("sys")
        if !(Array(sys.path) ?? []).contains(Self.pythonModuleURL.path) {
            sys.path.insert(1, Self.pythonModuleURL.path)
        }
        
        let module = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    let module = try Python.attemptImport("yt_dlp")
                    continuation.resume(returning: module)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let ytDlp = module.YoutubeDL(defaultOptions)
        self.pythonObject = ytDlp
        isPrepared = true
    }
    
    // 新增方法：检查模块文件是否存在
    private func isPythonModuleAvailable() -> Bool {
        FileManager.default.fileExists(atPath: Self.pythonModuleURL.path)
    }
    
    public func getVideoInfo(url: URL) async throws -> Info {
        
        if !isPythonModuleAvailable() {
            // 2. 自动下载模块
            try await Self.downloadPythonModule()
        }
        
        try await prepare()
        
        // 确保初始化成功
        guard let pythonObject = self.pythonObject else {
            throw YoutubeDLError.notInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    guard let pythonObject = self.pythonObject else {
                        throw NSError(domain: "YTDLPKit", code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "Not initialized"])
                    }
                    
                    let info = try pythonObject.extract_info.throwing.dynamicallyCall(
                        withKeywordArguments: ["": url.absoluteString,
                                             "download": false,
                                             "process": true]
                    )
                    let decoder = PythonDecoder()
                    let result = try decoder.decode(Info.self, from: info)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    fileprivate static func movePythonModule(_ location: URL) throws {
        do {
            try FileManager.default.removeItem(at: pythonModuleURL)
        }
        catch {
            let error = error as NSError
            if error.domain != NSCocoaErrorDomain || error.code != CocoaError.fileNoSuchFile.rawValue {
                print(#function, error)
            }
        }
        
        try FileManager.default.moveItem(at: location, to: pythonModuleURL)
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL, completionHandler: @escaping (Swift.Error?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { (location, response, error) in
            guard let location = location else {
                completionHandler(error)
                return
            }
            do {
                try movePythonModule(location)

                completionHandler(nil)
            }
            catch {
                print(#function, error)
                completionHandler(error)
            }
        }
        
        task.resume()
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL) async throws {
        let stopWatch = StopWatch(); defer { stopWatch.report() }
        if #available(iOS 15.0, *) {
            let (location, _) = try await URLSession.shared.download(from: url)
            try movePythonModule(location)
        } else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                downloadPythonModule(from: url) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func injectFakePopen() {
        do {
            let subprocess = try Python.attemptImport("subprocess")
            let os = try Python.attemptImport("os")
            let errno = try Python.attemptImport("errno")
            
            // 1. 创建返回元组的辅助函数
            let noneTuple: () -> PythonObject = {
                let none = Python.None
                return PythonObject(tupleOf: none, none) // 显式创建Python元组
            }
            
            // 2. 实现完整的Popen
            let fakePopen = PythonClass("FakePopen", members: [
                "__init__": PythonInstanceMethod { args in
                    print("[Popen模拟] 命令:", args[0])
                    return Python.None
                },
                
                "communicate": PythonInstanceMethod { _ in
                    return noneTuple() // 返回 (None, None)
                },
                
                "wait": PythonInstanceMethod { _ in
                    return 0
                },
                
                "poll": PythonInstanceMethod { _ in
                    return 0
                },
                
                "kill": PythonInstanceMethod { _ in
                    return Python.None
                },
                
                "terminate": PythonInstanceMethod { _ in
                    return Python.None
                },
                
                "__enter__": PythonInstanceMethod { args in
                    return args[0] // 返回self
                },
                
                "__exit__": PythonInstanceMethod { _ in
                    return Python.None
                }
            ]).pythonObject
            
            // 3. 替换原生Popen
            subprocess.Popen = fakePopen
            
            // 4. 优化环境变量
            os.environ["NO_COLOR"] = "1"
            os.environ["YTDLP_NO_UPDATE"] = "1"
            
        } catch {
            print("Popen补丁注入失败:", error)
        }
    }
    
}
