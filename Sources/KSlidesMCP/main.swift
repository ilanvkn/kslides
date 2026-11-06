import Foundation
import KSlidesCore

func descriptorURL() -> URL {
    if let path = ProcessInfo.processInfo.environment["KSLIDES_CONNECTION_FILE"] { return URL(fileURLWithPath:path) }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/io.github.ilanvkn.kslides/Data/Library/Application Support/KSlides/connection.json")
}
@MainActor func callApp(_ name: String, _ arguments: [String:Any]) async throws -> [String:Any] {
    let file = descriptorURL()
    guard let descriptor = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any], let raw = descriptor["url"] as? String, let url = URL(string:raw), url.host == "127.0.0.1", let token = descriptor["token"] as? String else { throw StudioError.invalid("Open KSlides before connecting your agent.") }
    var request = URLRequest(url:url); request.httpMethod = "POST"; request.timeoutInterval = 60
    request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
    request.setValue("application/json",forHTTPHeaderField:"Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject:["tool":name,"arguments":arguments])
    let (data,response) = try await URLSession.shared.data(for:request)
    guard (response as? HTTPURLResponse)?.statusCode == 200, let object = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw StudioError.invalid("KSlides connection failed. Open the app and retry.") }
    return object
}
func write(_ object: [String:Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject:object,options:.sortedKeys) else { return }
    FileHandle.standardOutput.write(data + Data([10]))
}

let geometryWorker = Task { await GeometryWorker.run() }
while let line = await Task.detached(priority:.utility,operation:{ readLine() }).value {
    guard line.utf8.count <= 24_000_000 else { write(["jsonrpc":"2.0","id":NSNull(),"error":["code":-32600,"message":"Request too large"]]); continue }
    do {
        guard let request = try JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any], request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            write(["jsonrpc":"2.0","id":NSNull(),"error":["code":-32600,"message":"Invalid JSON-RPC request"]]); continue
        }
        guard let id = request["id"] else { continue }
        let params = request["params"] as? [String:Any] ?? [:]
        var result: [String:Any]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? "2025-06-18"
            let supported = ["2024-11-05","2025-03-26","2025-06-18"]
            result = ["protocolVersion":supported.contains(requested) ? requested : "2025-06-18","capabilities":["tools":["listChanged":false]],"serverInfo":["name":"KSlides","version":"0.4.0"],"instructions":"KSlides is a native Mac educator studio. Open the app first. Read revisions before writes. Use kslides_render_scene for local NumPy/Blender geometry, then inspect the returned job ID. Keep this MCP connection open while rendering. Finished scenes are applied only at the captured lesson revision; use kslides_apply_scene with a fresh revision if the lesson changed. Image Playground textures can be chosen in Geometry Lab. Private teacher notes stay outside student slides."]
        case "ping": result = [:]
        case "tools/list": result = ["tools":ToolCatalog.tools()]
        case "tools/call":
            guard let name = params["name"] as? String, ToolCatalog.names.contains(name) else { write(["jsonrpc":"2.0","id":id,"error":["code":-32602,"message":"Unknown KSlides tool"]]); continue }
            do {
                let response = try await callApp(name,params["arguments"] as? [String:Any] ?? [:])
                if let error = response["error"] as? String { result = ["content":[["type":"text","text":error]],"isError":true] }
                else {
                    let value = response["result"] ?? [:]
                    let rendered = try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys,.fragmentsAllowed])
                    result = ["content":[["type":"text","text":String(decoding:rendered,as:UTF8.self)]],"isError":false]
                }
            } catch { result = ["content":[["type":"text","text":error.localizedDescription]],"isError":true] }
        default: write(["jsonrpc":"2.0","id":id,"error":["code":-32601,"message":"Method not found"]]); continue
        }
        write(["jsonrpc":"2.0","id":id,"result":result])
    } catch { write(["jsonrpc":"2.0","id":NSNull(),"error":["code":-32700,"message":"Parse error"]]) }
}
geometryWorker.cancel()
await geometryWorker.value
