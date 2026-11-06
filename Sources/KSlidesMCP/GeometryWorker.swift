import Foundation
import KSlidesCore

@MainActor enum GeometryWorker {
    static let blender = URL(fileURLWithPath:"/Applications/Blender.app/Contents/MacOS/Blender")
    static var script: URL {
        let executable = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
        let bundled = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/geometry_worker.py")
        if FileManager.default.fileExists(atPath:bundled.path) { return bundled }
        return URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/geometry_worker.py")
    }
    static func response(_ name: String, _ args: [String:Any]) async throws -> Any {
        let response = try await callApp(name,args)
        if let error = response["error"] as? String { throw StudioError.invalid(error) }
        return response["result"] ?? NSNull()
    }
    static func run() async {
        while !Task.isCancelled {
            do {
                let available = FileManager.default.isExecutableFile(atPath:blender.path) && FileManager.default.fileExists(atPath:script.path)
                if let job = try await response("_geometry_next",["available":available]) as? [String:Any] { await render(job) }
            } catch { /* App closed/restarting: the persisted queue resumes on reconnection. */ }
            try? await Task.sleep(for:.seconds(1))
        }
    }
    static func render(_ job: [String:Any]) async {
        guard let id = job["id"] as? String, let uuid = UUID(uuidString:id), let lease = job["lease"] as? String, let spec = job["scene"] as? [String:Any] else { return }
        let args: [String:Any] = ["job_id":id,"lease":lease]
        let out = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("KSlidesRenderer/\(uuid.uuidString)/\(lease)",isDirectory:true)
        let process = Process()
        do {
            try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
            try JSONSerialization.data(withJSONObject:spec).write(to:out.appendingPathComponent("scene.json"),options:.atomic)
            if let encoded = job["texture_base64"] as? String, let data = Data(base64Encoded:encoded) { try data.write(to:out.appendingPathComponent("texture.png"),options:.atomic) }
            let logURL = out.appendingPathComponent("render.log")
            FileManager.default.createFile(atPath:logURL.path,contents:nil)
            let log = try FileHandle(forWritingTo:logURL); defer { try? log.close() }
            process.executableURL = blender; process.arguments = ["--background","--python-exit-code","1","--python",script.path,"--",out.path]
            process.standardOutput = log; process.standardError = log
            try process.run()
            let started = Date()
            while process.isRunning {
                try await Task.sleep(for:.seconds(1))
                if Task.isCancelled || Date().timeIntervalSince(started)>120 { process.terminate(); throw StudioError.invalid("The render stopped before completion. Retry a smaller scene.") }
                let current = try await response("_geometry_ping",args) as? [String:Any]
                if current?["state"] as? String != "running" || current?["lease"] as? String != lease { process.terminate(); return }
            }
            guard process.terminationStatus == 0 else { throw StudioError.invalid("Blender could not render this scene. The local render log was preserved at \(logURL.path).") }
            let png = try Data(contentsOf:out.appendingPathComponent("render.png"))
            let blend = try Data(contentsOf:out.appendingPathComponent("scene.blend"))
            guard let report = try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("verification.json"))) as? [String:Any] else { throw StudioError.invalid("Missing numerical verification.") }
            var result = args; result["png"] = png.base64EncodedString(); result["blend"] = blend.base64EncodedString(); result["report"] = report
            _ = try await response("_geometry_complete",result)
        } catch {
            if process.isRunning { process.terminate() }
            var failure = args; failure["message"] = error.localizedDescription
            _ = try? await response("_geometry_fail",failure)
        }
    }
}
