import CryptoKit
import Foundation
import JavaScriptCore
import UniformTypeIdentifiers
import WebKit

/// Serves one app at `fishapp://<id>/`: its own files, nothing above its folder, and no other app.
/// The user's opening serves its published copy (`MiniAppPublisher`), compiled already. The agent's
/// browser has one that serves every app's working copy (`preview`), compiled as it is asked for,
/// so the agent sees what it just wrote; there the page keeps the browser's storage, not the user's.
/// JSX and TypeScript are compiled on the way out (Sucrase, in JavaScriptCore), so the agent writes
/// no build step. `react`, `react-dom` and `react/jsx-runtime` come from the app bundle
/// (MiniApps/Runtime, built by scripts/build-mini-app-runtime.sh) through an import map put at the
/// top of the page, beside a script that reports errors to the app.
final class MiniAppServer: NSObject, WKURLSchemeHandler {
    static let scheme = "fishapp"
    /// The message handler the page's error script posts to.
    static let messageName = "fishapp"

    /// The one app this server is for; nil in the agent's browser, which may open any.
    let appId: String?
    private let queue = DispatchQueue(label: "fishapp.server", qos: .userInitiated)
    /// Tasks WebKit stopped: answering them would throw.
    private var stopped = Set<ObjectIdentifier>()

    init(app: MiniApp) {
        appId = app.id
    }

    private init(anyApp: Void) {
        appId = nil
    }

    /// For the agent's browser: every app, each at its own address.
    @MainActor static let preview = MiniAppServer(anyApp: ())
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let id = ObjectIdentifier(task)
        queue.async { [self] in
            let response = respond(to: url)
            DispatchQueue.main.async { [self] in
                guard !stopped.contains(id) else { stopped.remove(id); return }
                let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": response.type,
                    "Content-Length": String(response.body.count),
                    "Cache-Control": "no-store",
                ])!
                task.didReceive(http)
                task.didReceive(response.body)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }

    private struct Response {
        var status = 200
        var type: String
        var body: Data

        static func text(_ text: String, type: String, status: Int = 200) -> Response {
            Response(status: status, type: "\(type); charset=utf-8", body: Data(text.utf8))
        }

        static let notFound = text("Not found", type: "text/plain", status: 404)
    }

    private func respond(to url: URL) -> Response {
        guard let host = url.host(), MiniApp.validId(host), appId == nil || host == appId else { return .notFound }
        let source = MiniAppStore.root.appending(path: host, directoryHint: .isDirectory).resolvingSymlinksInPath().standardizedFileURL
        // The user's: the published copy. Without one (it is made before opening), the working copy.
        let published = appId == nil ? nil : MiniAppPublisher.served(source)?.resolvingSymlinksInPath().standardizedFileURL
        let folder = published ?? source
        let path = url.path(percentEncoded: false)
        let asModule = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "module" } == true

        if path.hasPrefix("/__fishapp/") { return runtime(String(path.dropFirst("/__fishapp/".count))) }
        if path == "/" || path.isEmpty { return entry(in: folder) }

        guard let file = resolve(path, in: folder) else { return .notFound }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) else { return .notFound }
        if isDirectory.boolValue {
            let index = file.appending(path: "index.html")
            guard let data = try? Data(contentsOf: index) else { return .notFound }
            return .text(Self.inject(String(decoding: data, as: UTF8.self)), type: "text/html")
        }
        guard let data = try? Data(contentsOf: file) else { return .notFound }
        let ext = file.pathExtension.lowercased()
        let text = { String(decoding: data, as: UTF8.self) }

        // `import './style.css'` and `import data from './data.json'` (the compiler marks them).
        if asModule && ext == "css" {
            let css = Self.jsString(text())
            return .text("const s=document.createElement('style');s.textContent=\(css);document.head.appendChild(s);export default \(css);", type: "text/javascript")
        }
        if asModule && ext == "json" {
            return .text("export default \(text());", type: "text/javascript")
        }
        switch ext {
        case "html", "htm":
            return .text(Self.inject(text()), type: "text/html")
        case "jsx", "tsx", "ts", "js":
            if published != nil || file.lastPathComponent.hasSuffix(".min.js") { return .text(text(), type: "text/javascript") }
            return .text(MiniAppCompiler.shared.module(text(), file: file.lastPathComponent), type: "text/javascript")
        default:
            let type = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            return Response(type: type, body: data)
        }
    }

    /// A path inside the app's folder; nil for anything that leaves it, symbolic links included.
    private func resolve(_ path: String, in folder: URL) -> URL? {
        let file = folder.appending(path: String(path.drop { $0 == "/" })).resolvingSymlinksInPath().standardizedFileURL
        let base = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        return file.path.hasPrefix(base) || file.path == folder.path ? file : nil
    }

    /// `index.html`, or a page that renders the component `App.jsx` (or .tsx…) exports.
    private func entry(in folder: URL) -> Response {
        if let data = try? Data(contentsOf: folder.appending(path: "index.html")) {
            return .text(Self.inject(String(decoding: data, as: UTF8.self)), type: "text/html")
        }
        guard let component = MiniApp.componentEntries.first(where: { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }) else {
            return .notFound
        }
        let page = """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>html{-webkit-text-size-adjust:100%}body{margin:0;font-family:-apple-system,system-ui,sans-serif}</style>
        </head><body><div id="root"></div>
        <script type="module">
        import { createElement } from 'react';
        import { createRoot } from 'react-dom/client';
        import App from './\(component)';
        createRoot(document.getElementById('root')).render(createElement(App));
        </script></body></html>
        """
        return .text(Self.inject(page), type: "text/html")
    }

    private func runtime(_ name: String) -> Response {
        guard name.hasPrefix("miniapp-"), name.hasSuffix(".js"),
              let url = Bundle.main.url(forResource: String(name.dropLast(3)), withExtension: "js"),
              let data = try? Data(contentsOf: url) else { return .notFound }
        return Response(type: "text/javascript; charset=utf-8", body: data)
    }

    /// The import map and the error reporter, first thing in `<head>`: an import map must come
    /// before any module script.
    static func inject(_ html: String) -> String {
        let imports = [
            "react": "/__fishapp/miniapp-react.js",
            "react-dom": "/__fishapp/miniapp-react-dom.js",
            "react-dom/client": "/__fishapp/miniapp-react-dom-client.js",
            "react/jsx-runtime": "/__fishapp/miniapp-jsx-runtime.js",
            "react/jsx-dev-runtime": "/__fishapp/miniapp-jsx-runtime.js",
        ]
        let map = String(decoding: try! JSONSerialization.data(withJSONObject: ["imports": imports], options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        let head = """
        <script type="importmap">\(map)</script>
        <script>(function(){
        var post=function(m){console.error(String(m));try{window.webkit.messageHandlers.\(messageName).postMessage(String(m).slice(0,2000))}catch(e){}};
        var own=function(f){return f&&f.indexOf('/__fishapp/')<0};
        var at=function(err,file,line){
        var frames=String(err&&err.stack||'').split('\\n');
        for(var i=0;i<frames.length;i++){var m=frames[i].match(/fishapp:\\/\\/[^/]+(\\/[^:?]+)[^:]*:(\\d+)/);if(m&&own(m[1]))return ' ('+m[1].slice(1)+':'+m[2]+')'}
        var path=file?file.replace(/^fishapp:\\/\\/[^/]+/,''):'';
        return own(path)&&path!=='/'?' ('+path.slice(1)+(line?':'+line:'')+')':''};
        window.addEventListener('error',function(e){
        var t=e.target;
        if(t&&t!==window&&(t.src||t.href)){post('无法加载 '+(t.src||t.href));return}
        post((e.error&&e.error.message||e.message||'Error')+at(e.error,e.filename,e.lineno))},true);
        window.addEventListener('unhandledrejection',function(e){var r=e.reason;post((r&&r.message||String(r))+at(r))});
        })();</script>
        """
        if let range = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: range, with: html[range] + head)
        }
        if let range = html.range(of: "<html[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: range, with: html[range] + "<head>" + head + "</head>")
        }
        return head + html
    }

    static func jsString(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}

/// JSX and TypeScript to the JavaScript WebKit runs, with Sucrase (MiniApps/Runtime). One context,
/// on one queue; the output is kept per file until the source changes.
final class MiniAppCompiler: @unchecked Sendable {
    static let shared = MiniAppCompiler()

    struct Failure: Error { let message: String }

    private let lock = NSLock()
    private var context: JSContext?
    private var cache: [String: String] = [:]

    /// Loads Sucrase ahead of the first app: parsing it takes a moment the user would see.
    func warmUp() {
        DispatchQueue.global(qos: .utility).async { [self] in
            lock.lock()
            defer { lock.unlock() }
            if context == nil { _ = load() }
        }
    }

    /// The module WebKit runs for `source`: compiled, or one that throws the compiler's error, so
    /// the page reports it as any other.
    func module(_ source: String, file: String) -> String {
        switch compile(source, file: file) {
        case .success(let code): return code
        case .failure(let error):
            return "throw new SyntaxError(\(MiniAppServer.jsString("\(file): \(error.message)")));"
        }
    }

    /// Compiled files, kept across launches: an app opens without compiling what has not changed.
    private static let diskCache: URL = {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "miniapp-compiled", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    func compile(_ source: String, file: String) -> Result<String, Failure> {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(file)\u{0}\(source)"
        if let hit = cache[key] { return .success(hit) }
        let stored = Self.diskCache.appending(path: SHA256.hash(data: Data((Self.version + key).utf8)).map { String(format: "%02x", $0) }.joined() + ".js")
        if let data = try? Data(contentsOf: stored) {
            let code = String(decoding: data, as: UTF8.self)
            cache[key] = code
            return .success(code)
        }
        guard let context = context ?? load() else { return .failure(Failure(message: "compiler unavailable")) }
        let ext = (file as NSString).pathExtension.lowercased()
        let transforms = ext == "ts" || ext == "tsx" ? ["jsx", "typescript"] : ["jsx"]
        context.exception = nil
        let result = context.objectForKeyedSubscript("sucrase")?.objectForKeyedSubscript("transform")?.call(withArguments: [
            source, ["transforms": transforms, "jsxRuntime": "automatic", "production": true, "filePath": file] as [String: Any],
        ])
        if let exception = context.exception {
            context.exception = nil
            return .failure(Failure(message: exception.toString()))
        }
        guard let code = result?.objectForKeyedSubscript("code")?.toString() else { return .failure(Failure(message: "no output")) }
        let marked = Self.markAssetImports(code)
        if cache.count > 200 { cache.removeAll() }
        cache[key] = marked
        try? Data(marked.utf8).write(to: stored, options: .atomic)
        return .success(marked)
    }

    /// Part of each cache entry's name and of a published copy's fingerprint: a change to how files
    /// are compiled starts the cache over and publishes every app again.
    static let version = "sucrase-3.35.1-1\u{0}"

    private func load() -> JSContext? {
        guard let url = Bundle.main.url(forResource: "miniapp-sucrase", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else { return nil }
        context.evaluateScript(script)
        guard context.exception == nil else { return nil }
        self.context = context
        return context
    }

    /// Relative `.css` and `.json` imports become modules the server writes (`?module`).
    static func markAssetImports(_ code: String) -> String {
        let pattern = #"((?:\bfrom|\bimport)\s*)(["'])(\.{1,2}/[^"'?]+\.(?:css|json))\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return code }
        return regex.stringByReplacingMatches(in: code, range: NSRange(code.startIndex..., in: code), withTemplate: "$1$2$3?module$2")
    }
}
