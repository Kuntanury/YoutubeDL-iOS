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

// https://github.com/pvieito/PythonKit/pull/30#issuecomment-751132191
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)

func loadSymbol<T>(_ name: String) -> T {
    unsafeBitCast(dlsym(RTLD_DEFAULT, name), to: T.self)
}

let Py_IsInitialized: @convention(c) () -> Int32 = loadSymbol("Py_IsInitialized")

let chunkSize: Int64 = 10_485_760 // https://github.com/yt-dlp/yt-dlp/blob/720c309932ea6724223d0a6b7781a0e92a74262c/yt_dlp/extractor/youtube.py#L2552

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
    "verbose": true,
    // Allow yt-dlp to fetch EJS scripts if needed (desktop/other platforms)
    "remote_components": ["ejs:github"],
]

public enum YoutubeDLError: Error {
    case noPythonModule
    case canceled
}

open class YoutubeDL: NSObject {
    public static let latestDownloadURL =
    URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp")!
    public static let latestDownloadMirrorURL =
    URL(string: "https://s.fanyiou.com/public/ytdlp/yt-dlp")!

    public static let appleWebKitJSIPluginDownloadURL =
    URL(string: "https://github.com/grqz/yt-dlp-apple-webkit-jsi/releases/latest/download/yt-dlp-apple-webkit-jsi.zip")!

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

    public static var pluginDirectoryURL: URL = {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("io.github.kewlbear.youtubedl-ios") else { fatalError() }
        let pluginsDir = directory.appendingPathComponent("yt-dlp/plugins", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
        return pluginsDir
    }()
    
    public static var appleWebKitJSIPluginZipURL: URL {
        pluginDirectoryURL.appendingPathComponent("yt-dlp-apple-webkit-jsi.zip")
    }

    public static var appleWebKitJSIPluginExtractedURL: URL {
        pluginDirectoryURL.appendingPathComponent("yt-dlp-apple-webkit-jsi", isDirectory: true)
    }

    public var version: String?
    
    private var cookieFileURL: URL?

    public func setCookieFile(_ url: URL) {
        self.cookieFileURL = url
        UserDefaults.standard.set(url.path, forKey: "yt_dlp_cookiefile_path")
        self.pythonObject = nil
        self.options = nil
    }

    private func loadCookieFileIfNeeded() {
        if cookieFileURL == nil,
           let path = UserDefaults.standard.string(forKey: "yt_dlp_cookiefile_path") {
            cookieFileURL = URL(fileURLWithPath: path)
        }
    }

    internal var pythonObject: PythonObject?

    internal var options: PythonObject?
    
    private let ytDlpVersionKey = "yt_dlp_version"
    
    public override init() {
        super.init()
    }
    
    func loadPythonModule(downloadPythonModule: Bool = true) async throws -> PythonObject {
        if Py_IsInitialized() == 0 {
            PythonSupport.initialize()
        }
        
        let moduleExists = FileManager.default.fileExists(
            atPath: Self.pythonModuleURL.path
        )

        do {
            let latestVersion = try await Self.fetchLatestVersion()
            let localVersion = self.getLocalVersion()

            if !moduleExists || localVersion == nil || latestVersion != localVersion {
                try await Self.downloadPythonModule()
                self.setLocalVersion(latestVersion)
            }
        } catch {
            if !moduleExists {
                guard downloadPythonModule else {
                    throw YoutubeDLError.noPythonModule
                }
                try await Self.downloadPythonModule()
            } else {
                throw error
            }
        }
        await ensureAppleWebKitJSIPluginInstalled()
        await ensureAppleWebKitJSIPluginExtractedAndPatched()
        let extractedPluginsDir = Self.appleWebKitJSIPluginExtractedURL.appendingPathComponent("yt_dlp_plugins", isDirectory: true)
        print("[yt-dlp] extracted plugin root:", Self.appleWebKitJSIPluginExtractedURL.path,
              "yt_dlp_plugins exists:", FileManager.default.fileExists(atPath: extractedPluginsDir.path))
        
        let sys = try Python.attemptImport("sys")
        let currentPath: [String] = Array(sys.path) ?? []
        if !currentPath.contains(Self.pythonModuleURL.path) {
            injectFakePopen(handler: popenHandler)
            
            sys.path.insert(1, Self.pythonModuleURL.path)
            
        }
        
        
        
        let pythonModule = try Python.attemptImport("yt_dlp")

        // Patch apple-webkit-jsi: avoid crashing in set_logger due to generator priming issues
        // (Some iOS/Python environments hit "can't send non-None value to a just-started generator" during set_logger)
        runSimpleString("""
try:
    import inspect
    import yt_dlp_plugins.webkit_jsi.lib.easy as _wk_easy

    def _no_op_set_logger(self, new_logger=None):
        return None

    for _name, _obj in vars(_wk_easy).items():
        if inspect.isclass(_obj) and hasattr(_obj, 'set_logger'):
            try:
                setattr(_obj, 'set_logger', _no_op_set_logger)
            except Exception:
                pass
except Exception:
    pass
""")

        version = String(pythonModule.version.__version__)
        return pythonModule
    }
    
    public static func fetchLatestVersion() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TransGull/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                throw URLError(.cannotParseResponse)
            }
            
            return tagName.replacingOccurrences(of: "v", with: "")
        } catch {
            print("\(error.localizedDescription)")
        }
        
        let mirrorURL = URL(string: "http://s.fanyiou.com/public/ytdlp/latest.json")!
        var mirrorRequest = URLRequest(url: mirrorURL)
        mirrorRequest.timeoutInterval = 5
        mirrorRequest.setValue("TransGull/1.0", forHTTPHeaderField: "User-Agent")
        
        let (mirrorData, mirrorResponse) = try await URLSession.shared.data(for: mirrorRequest)
        
        guard let httpResponse = mirrorResponse as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: mirrorData) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        return tagName.replacingOccurrences(of: "v", with: "")
    }
    
    func getLocalVersion() -> String? {
        UserDefaults.standard.string(forKey: ytDlpVersionKey)
    }

    func setLocalVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: ytDlpVersionKey)
    }
    
    func injectFakePopen(handler: PythonFunction) {
        runSimpleString("""
            import errno
            import os
            import io

            class Pop:
                def __init__(self, *args, **kwargs):
                    print('Popen.__init__:', self, args)#, kwargs)
                    self.__args = args
                    self.returncode = 0
                    # Provide file-like stdout/stderr so callers like ctypes.util.find_library can read
                    self.stdout = io.BytesIO(b'')
                    self.stderr = io.BytesIO(b'')

                def communicate(self, *args, **kwargs):
                    print('Popen.communicate:', self, args, kwargs)
                    out, err = self.handler(self, self.__args)
                    if out is None:
                        out = ''
                    if err is None:
                        err = ''
                    if isinstance(out, str):
                        out = out.encode('utf-8')
                    if isinstance(err, str):
                        err = err.encode('utf-8')
                    # Keep stdout/stderr readable after communicate
                    self.stdout = io.BytesIO(out)
                    self.stderr = io.BytesIO(err)
                    return out, err

                def kill(self):
                    print('Popen.kill:', self)

                def wait(self, **kwargs):
                    print('Popen.wait:', self, kwargs)
                    return self.returncode

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

        if let args: [String] = Array(args[1][0]) {
            popen.returncode = PythonObject(0)

            let builtins = Python.import("builtins")
            let emptyBytes = builtins.bytes(PythonObject(""), PythonObject("utf-8"))

            // ctypes.util.find_library may call /sbin/ldconfig -p and read from p.stdout
            if args.count >= 2, args[0] == "/sbin/ldconfig", args[1] == "-p" {
                return Python.tuple([emptyBytes, emptyBytes])
            }

            // ld checks like: ld -t -o /dev/null -ldl
            if args.first == "ld" {
                return Python.tuple([emptyBytes, emptyBytes])
            }

            return Python.tuple([emptyBytes, emptyBytes])
        }
        let builtins = Python.import("builtins")
        let emptyBytes = builtins.bytes(PythonObject(""), PythonObject("utf-8"))
        return Python.tuple([emptyBytes, emptyBytes])
    }
    
    func makePythonObject(_ options: PythonObject? = nil, initializePython: Bool = true) async throws -> PythonObject {
//        let pythonModule = try await loadPythonModule()
//        let options = options ?? defaultOptions
//        pythonObject = pythonModule.YoutubeDL(options)
//        self.options = options
//        return pythonObject!
        let pythonModule = try await loadPythonModule()
        loadCookieFileIfNeeded()

        var merged: PythonObject = defaultOptions
        if let opt = options {
            merged = opt
        }
        if let cookieFileURL {
            merged["cookiefile"] = PythonObject(cookieFileURL.path)
        }

        // Prefer extracted (patched) plugin folder.
        // NOTE: yt-dlp expects each plugin_dir to be a *parent* directory that contains a `yt_dlp_plugins` package.
        let extractedRoot = Self.appleWebKitJSIPluginExtractedURL
        let extractedPluginsPkg = extractedRoot.appendingPathComponent("yt_dlp_plugins", isDirectory: true)

        let chosenPluginDir: String
        if FileManager.default.fileExists(atPath: extractedPluginsPkg.path) {
            chosenPluginDir = extractedRoot.path
        } else {
            chosenPluginDir = Self.pluginDirectoryURL.path
        }

        // Make sure we pass a real Python list, not a Swift array (yt-dlp is strict about plugin_dirs)
        merged["plugin_dirs"] = Python.list([PythonObject(chosenPluginDir), PythonObject("default")])

        // Do NOT set any js_runtimes on iOS. Ensure the key is removed entirely.
        do {
            let hasKey = Bool(PythonObject(merged.__contains__("js_runtimes"))) ?? false
            if hasKey {
                _ = merged.pop("js_runtimes")
            }
        }

        pythonObject = pythonModule.YoutubeDL(merged)
        print("[yt-dlp] plugin_dirs:", merged["plugin_dirs"], "has js_runtimes:", Bool(PythonObject(merged.__contains__("js_runtimes"))) ?? false)
        self.options = merged
        return pythonObject!
    }

    private func ensureAppleWebKitJSIPluginInstalled() async {
        let pluginZip = Self.appleWebKitJSIPluginZipURL
        if FileManager.default.fileExists(atPath: pluginZip.path) {
            return
        }
        do {
            if #available(iOS 15.0, *) {
                let (location, _) = try await URLSession.shared.download(from: Self.appleWebKitJSIPluginDownloadURL)
                // Ensure parent exists
                try? FileManager.default.createDirectory(at: Self.pluginDirectoryURL, withIntermediateDirectories: true)
                removeItem(at: pluginZip)
                try FileManager.default.moveItem(at: location, to: pluginZip)
                print("[yt-dlp] Installed plugin: yt-dlp-apple-webkit-jsi ->", pluginZip.path)
            } else {
                // Fallback on earlier versions
            }
        } catch {
            print("[yt-dlp] Failed to download yt-dlp-apple-webkit-jsi:", error.localizedDescription)
        }
    }
    
    open func getInfo(url: URL) async throws -> (Info) {
        let pythonObject: PythonObject
        if let _pythonObject = self.pythonObject {
            pythonObject = _pythonObject
        } else {
            pythonObject = try await makePythonObject()
        }

        // apple-webkit-jsi constructs a WKWebView and must run on the main thread
        return try await MainActor.run {
            let decoder = PythonDecoder()
            let info = try pythonObject.extract_info.throwing.dynamicallyCall(withKeywordArguments: [
                "": url.absoluteString,
                "download": false,
                "process": true
            ])
            return try decoder.decode(Info.self, from: info)
        }
    }
    
    fileprivate static func movePythonModule(_ location: URL) throws {
        removeItem(at: pythonModuleURL)
        
        try FileManager.default.moveItem(at: location, to: pythonModuleURL)
    }
    
    public static func downloadPythonModule(from url: URL = latestDownloadURL, completionHandler: @escaping (Swift.Error?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { (location, response, error) in
            if let location = location {
                do {
                    try movePythonModule(location)
                    completionHandler(nil)
                    return
                } catch {
                    print(#function, error)
                    completionHandler(error)
                    return
                }
            }
            
            let mirrorTask = URLSession.shared.downloadTask(with: latestDownloadMirrorURL) { (mirrorLocation, mirrorResponse, mirrorError) in
                guard let mirrorLocation = mirrorLocation else {
                    completionHandler(mirrorError ?? error)
                    return
                }
                do {
                    try movePythonModule(mirrorLocation)
                    completionHandler(nil)
                } catch {
                    print(#function, error)
                    completionHandler(error)
                }
            }
            mirrorTask.resume()
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
    
    private func ensureAppleWebKitJSIPluginExtractedAndPatched() async {
        let zipURL = Self.appleWebKitJSIPluginZipURL
        let extractURL = Self.appleWebKitJSIPluginExtractedURL

        // Extract once (if needed). Even if the zip is removed later, we may still need to patch.
        let marker = extractURL.appendingPathComponent(".extracted")
        let extractedAlready = FileManager.default.fileExists(atPath: marker.path)

        if !extractedAlready {
            // If not extracted yet, we need the zip to proceed
            guard FileManager.default.fileExists(atPath: zipURL.path) else {
                return
            }
            do {
                try? FileManager.default.removeItem(at: extractURL)
                try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true)

                // Use Python's zipfile to extract (no external libs)
                let zipPath = zipURL.path.replacingOccurrences(of: "\\", with: "\\\\")
                let outPath = extractURL.path.replacingOccurrences(of: "\\", with: "\\\\")
                runSimpleString("""
import zipfile, os
_zip = r'''\(zipPath)'''
_out = r'''\(outPath)'''
os.makedirs(_out, exist_ok=True)
with zipfile.ZipFile(_zip, 'r') as z:
    z.extractall(_out)
""")

                try Data("ok".utf8).write(to: marker, options: .atomic)
                // Remove the zip after extraction so yt-dlp loads the extracted (patched) plugin instead of the zip
                removeItem(at: zipURL)
                print("[yt-dlp] Extracted plugin to:", extractURL.path)
            } catch {
                print("[yt-dlp] Failed to extract yt-dlp-apple-webkit-jsi:", error.localizedDescription)
                return
            }
        }

        // Patch api.py to guard generator priming issues on some iOS/Python runtimes
        let apiPy = extractURL
            .appendingPathComponent("yt_dlp_plugins", isDirectory: true)
            .appendingPathComponent("webkit_jsi", isDirectory: true)
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("api.py")

        guard FileManager.default.fileExists(atPath: apiPy.path) else { return }

        let apiPath = apiPy.path.replacingOccurrences(of: "\\", with: "\\\\")
        runSimpleString("""
try:
    _p = r'''\(apiPath)'''
    with open(_p, 'r', encoding='utf-8') as f:
        s = f.read()

    if '_safe_gen_send' not in s and 'gen_run.send(args)' in s:
        helper_lines = [
            "",
            "# --- TransGull patch: guard generator priming (iOS/PythonKit)",
            "",
            "def _safe_gen_send(_gen, _args):",
            "    try:",
            "        return _gen.send(_args)",
            "    except TypeError as _e:",
            "        if 'just-started generator' in str(_e):",
            "            try:",
            "                _gen.send(None)",
            "            except Exception:",
            "                pass",
            "            return _gen.send(_args)",
            "        raise",
            "# --- end patch",
            ""
        ]
        helper = "\\n".join(helper_lines)

        lines = s.splitlines(True)
        insert_at = 0
        for i, line in enumerate(lines):
            if line.strip():
                insert_at = i + 1
                break
        lines.insert(insert_at, helper)
        s2 = ''.join(lines)
        s2 = s2.replace('yield lambda *args: gen_run.send(args)', 'yield lambda *args: _safe_gen_send(gen_run, args)')

        with open(_p, 'w', encoding='utf-8') as f:
            f.write(s2)
        print('PATCHED api.py:', _p)
    else:
        print('SKIP patch api.py (already patched or pattern missing):', _p)
except Exception as _e:
    print('FAILED patch api.py:', _e)
""")
        // Verify patch outcome (log whether the old callsite still exists)
        runSimpleString("""
try:
    _p = r'''\(apiPath)'''
    with open(_p, 'r', encoding='utf-8') as f:
        _s = f.read()
    print('VERIFY api.py contains gen_run.send(args):', 'gen_run.send(args)' in _s)
    print('VERIFY api.py contains _safe_gen_send:', '_safe_gen_send' in _s)
except Exception as _e:
    print('FAILED verify api.py:', _e)
""")
        print("[yt-dlp] Patched plugin api.py at:", apiPy.path)
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
