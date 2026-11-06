import Foundation
@preconcurrency import Network
import KSlidesCore

@MainActor final class AgentServer {
    unowned let store: StudioStore
    var listener: NWListener?
    let token = UUID().uuidString + UUID().uuidString
    init(store: StudioStore) { self.store = store }
    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host:.ipv4(.loopback), port:.any)
        let listener = try NWListener(using:params)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port else { return }
                    do {
                        let descriptor: [String:Any] = ["url":"http://127.0.0.1:\(port.rawValue)/rpc","token":self.token,"pid":ProcessInfo.processInfo.processIdentifier]
                        let url = self.store.root.appendingPathComponent("connection.json")
                        try JSONSerialization.data(withJSONObject:descriptor).write(to:url,options:.atomic)
                        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
                        self.store.serverStatus = "Ready for Codex & AI agents"
                    } catch { self.store.error = error.localizedDescription }
                case .failed(let error): self.store.serverStatus = "Connection failed"; self.store.error = error.localizedDescription
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                let request = HTTPRequest(connection:connection, server:self)
                request.start()
            }
        }
        listener.start(queue:.global(qos:.userInitiated))
    }
    func result(_ name: String, _ a: [String:Any]) throws -> Any {
        if ["_geometry_next","_geometry_ping","_geometry_complete","_geometry_fail"].contains(name) { return try store.geometryRPC(name,a) }
        guard ToolCatalog.names.contains(name) else { throw StudioError.invalid("Unknown KSlides tool.") }
        guard let spec = ToolCatalog.tools().first(where: { $0["name"] as? String == name }), let schema = spec["inputSchema"] as? [String:Any], let props = schema["properties"] as? [String:Any] else { throw StudioError.invalid("Tool unavailable.") }
        guard Set(a.keys).isSubset(of:Set(props.keys)) else { throw StudioError.invalid("Unexpected tool argument.") }
        for field in schema["required"] as? [String] ?? [] { guard a[field] != nil else { throw StudioError.invalid("Missing argument: \(field)") } }
        for (field, value) in a {
            guard let prop = props[field] as? [String:Any], let type = prop["type"] as? String else { continue }
            let good: Bool
            switch type {
            case "string": good = value is String
            case "integer": good = (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.rounded() == $0.doubleValue } ?? false
            case "object": good = value is [String:Any]
            case "array": good = value is [String]
            default: good = false
            }
            guard good else { throw StudioError.invalid("Invalid argument type: \(field)") }
            if let allowed = prop["enum"] as? [String], let text = value as? String, !allowed.contains(text) { throw StudioError.invalid("Invalid choice for \(field).") }
        }
        func uuid(_ key: String) throws -> UUID { guard let text = a[key] as? String, let id = UUID(uuidString:text) else { throw StudioError.invalid("Invalid UUID: \(key)") }; return id }
        func encoded(_ value: Lesson) throws -> Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
        func current() throws -> Lesson { try store.lesson(uuid("lesson_id")) }
        func revision() throws -> Int { guard let r = a["expected_revision"] as? Int, r > 0 else { throw StudioError.invalid("expected_revision is required.") }; return r }
        switch name {
        case "kslides_status": return ["app":"KSlides","version":"0.4.0","lessons":store.lessons.count,"connection":"ready","tools":ToolCatalog.names,"geometry_rendering":"Use kslides_render_scene for local mathematical scenes; inspect kslides_render_job for completion.","data_location":store.root.path]
        case "kslides_geometry_engines","kslides_render_scene","kslides_render_job","kslides_cancel_render","kslides_apply_scene","kslides_geometry_texture": return try store.geometryRPC(name,a)
        case "kslides_design_catalog":
            return ["layouts":SlideLayout.allCases.map { ["id":$0.rawValue,"name":$0.label,"composition":$0.guidance] },"typography":TypeStyle.allCases.map { ["id":$0.rawValue,"heading":$0.heading,"body":$0.body] },"worlds":World.allCases.map { ["id":$0.rawValue,"direction":$0.visualDescription,"default_typography":TypeStyle.themeDefault($0).rawValue] },"body_structure":"Separate cards with a blank line. Concept/compare have two cards; guided sequence has up to three. Other native layouts preserve body as a text box. Illustrated is a rendering mode for complete authored images: title/body are source references, with no native overlays. It is not a repeated composition."]
        case "kslides_review_lesson":
            let value = try current()
            var warnings: [[String:Any]] = []
            for (index,slide) in value.slides.enumerated() {
                if let issue = SlideDrawing.fitIssue(slide,lesson:value) { warnings.append(["slide":index+1,"kind":"text_fit","message":issue]) }
                if slide.artwork == nil && ["cover","spotlight","full","illustrated"].contains(slide.layout) { warnings.append(["slide":index+1,"kind":"artwork","message":"This scene composition has no attached artwork."]) }
                if !["illustrated","geometry"].contains(slide.layout) && index >= 2 && value.slides[index-1].layout == slide.layout && value.slides[index-2].layout == slide.layout { warnings.append(["slide":index+1,"kind":"repetition","message":"Three consecutive slides repeat the same composition."]) }
            }
            return ["lesson_id":value.id.uuidString,"revision":value.revision,"warnings":warnings,"compositions":Set(value.slides.map(\.layout)).sorted(),"typography":Set(value.slides.map { $0.typography ?? TypeStyle.themeDefault(value.world).rawValue }).sorted(),"text_fit_ok":!warnings.contains { $0["kind"] as? String == "text_fit" },"image_first_slides":value.slides.enumerated().compactMap { $0.element.layout == "illustrated" ? $0.offset+1 : nil },"scope":"Native text fit and structure only. Lettering within illustrated images must be visually checked by the author; subject accuracy and curriculum alignment require educator review."]
        case "kslides_list_lessons": return store.lessons.map { ["id":$0.id.uuidString,"title":$0.title,"topic":$0.topic,"audience":$0.audience,"revision":$0.revision,"slide_count":$0.slides.count,"world":$0.world.rawValue] as [String:Any] }
        case "kslides_get_lesson": return try encoded(current())
        case "kslides_create_lesson":
            let value = Lesson(title:a["title"] as? String ?? "", topic:a["topic"] as? String ?? "", audience:a["audience"] as? String ?? "", goals:a["goals"] as? String ?? "", sourceContent:a["source_content"] as? String ?? "", world:World(rawValue:a["world"] as? String ?? "") ?? .explorer)
            return try encoded(store.create(value))
        case "kslides_update_lesson":
            var value = try current()
            if let s = a["title"] as? String { value.title = s }; if let s = a["topic"] as? String { value.topic = s }; if let s = a["audience"] as? String { value.audience = s }
            if let s = a["goals"] as? String { value.goals = s }; if let s = a["source_content"] as? String { value.sourceContent = s }; if let s = a["world"] as? String, let world = World(rawValue:s) { value.world = world }
            return try encoded(store.replace(value, expected:revision()))
        case "kslides_upsert_slide":
            var value = try current()
            let id = a["slide_id"] != nil ? try uuid("slide_id") : UUID()
            let index = value.slides.firstIndex { $0.id == id }
            if a["slide_id"] != nil && index == nil { throw StudioError.invalid("Slide not found.") }
            var slide = index.map { value.slides[$0] } ?? Slide(id:id, title:a["title"] as? String ?? "")
            slide.title = a["title"] as? String ?? slide.title
            if let s = a["body"] as? String { slide.body = s }; if let s = a["phase"] as? String { slide.phase = s }; if let s = a["purpose"] as? String { slide.purpose = s }
            if let s = a["student_action"] as? String { slide.studentAction = s }; if let s = a["teacher_notes"] as? String { slide.teacherNotes = s }; if let s = a["image_prompt"] as? String { slide.imagePrompt = s }
            if let s = a["duration_seconds"] as? Int { slide.durationSeconds = s }; if let s = a["layout"] as? String { slide.layout = s }; if let s = a["typography"] as? String { slide.typography = s == "theme" ? nil : s }; if a["reveal_for"] != nil { slide.revealFor = try uuid("reveal_for") }
            if let index { value.slides[index] = slide } else { value.slides.append(slide) }
            return try encoded(store.replace(value, expected:revision()))
        case "kslides_reorder_slides":
            var value = try current()
            guard let raw = a["slide_ids"] as? [String] else { throw StudioError.invalid("slide_ids required.") }
            let ids = raw.compactMap(UUID.init(uuidString:))
            guard ids.count == value.slides.count, Set(ids) == Set(value.slides.map(\.id)), Set(ids).count == ids.count else { throw StudioError.invalid("Provide every slide UUID exactly once.") }
            value.slides = ids.compactMap { id in value.slides.first { $0.id == id } }
            return try encoded(store.replace(value, expected:revision()))
        case "kslides_attach_artwork":
            let data: Data
            guard (a["image_base64"] != nil) != (a["image_path"] != nil) else { throw StudioError.invalid("Provide exactly one image source.") }
            if let text = a["image_base64"] as? String { guard let decoded = Data(base64Encoded:text) else { throw StudioError.invalid("Invalid base64 image.") }; data = decoded }
            else if let path = a["image_path"] as? String { data = try Data(contentsOf:URL(fileURLWithPath:path)) }
            else { throw StudioError.invalid("Image source required.") }
            return try encoded(store.attach(data,to:uuid("lesson_id"),slideID:uuid("slide_id"),expected:revision(),provenance:a["provenance"] as? String ?? ""))
        case "kslides_image_brief":
            let value = try current(); let id = try uuid("slide_id")
            guard let slide = value.slides.first(where: { $0.id == id }) else { throw StudioError.invalid("Slide not found.") }
            return ["prompt":value.prompt(for:slide),"rendering":slide.layout == "illustrated" ? "complete illustrated slide" : "editable native overlays","overlay_title":slide.layout == "illustrated" ? "" : slide.title,"overlay_body":slide.layout == "illustrated" ? "" : slide.body,"source_title":slide.title,"source_body":slide.body,"lesson_revision":value.revision,"generation_status":"awaiting agent image generation"]
        case "kslides_import_plan":
            guard let plan = a["plan"] as? [String:Any] else { throw StudioError.invalid("plan object required.") }
            return try encoded(store.importPlan(plan))
        case "kslides_export":
            let lesson = try current(); let format = a["format"] as? String ?? ""
            let paths = try Exporter.export(lesson,format:format,store:store)
            store.message = "Exported \(lesson.title)"
            return ["format":format,"paths":paths.map(\.path),"revision":lesson.revision]
        default: throw StudioError.invalid("Unsupported tool.")
        }
    }
}

@MainActor private final class HTTPRequest {
    let connection: NWConnection
    unowned let server: AgentServer
    var data = Data()
    var completed = false
    init(connection: NWConnection, server: AgentServer) { self.connection = connection; self.server = server }
    func start() {
        connection.start(queue:.global(qos:.userInitiated))
        receive()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(30))
            if let self, !self.completed { self.completed = true; self.connection.cancel() }
        }
    }
    func receive() {
        connection.receive(minimumIncompleteLength:1, maximumLength:65536) { [self] content, _, done, error in
            Task { @MainActor in
                if let content { self.data.append(content) }
                if self.data.count > 24_000_000 { self.respond(413,["error":"Request too large"]); return }
                if let marker = self.data.range(of:Data("\r\n\r\n".utf8)), let header = String(data:self.data[..<marker.lowerBound], encoding:.utf8) {
                    let lines = header.components(separatedBy:"\r\n")
                    var headers: [String:String] = [:]
                    for line in lines.dropFirst() { let pair = line.split(separator:":",maxSplits:1); if pair.count == 2 { headers[String(pair[0]).lowercased()] = pair[1].trimmingCharacters(in:.whitespaces) } }
                    guard lines.first == "POST /rpc HTTP/1.1", headers["origin"] == nil else { self.respond(403,["error":"Only local authenticated bridge requests are supported"]); return }
                    guard headers["authorization"] == "Bearer \(self.server.token)" else { self.respond(401,["error":"Authentication required"]); return }
                    guard let length = Int(headers["content-length"] ?? ""), (0...24_000_000).contains(length) else { self.respond(400,["error":"Valid content length required"]); return }
                    if self.data.count - marker.upperBound >= length {
                        do {
                            let body = self.data.subdata(in:marker.upperBound..<(marker.upperBound + length))
                            guard let request = try JSONSerialization.jsonObject(with:body) as? [String:Any], let name = request["tool"] as? String else { throw StudioError.invalid("Invalid request") }
                            let result = try self.server.result(name,request["arguments"] as? [String:Any] ?? [:])
                            self.respond(200,["result":result])
                        } catch { self.respond(200,["error":error.localizedDescription]) }
                        return
                    }
                }
                if done || error != nil { self.completed = true; self.connection.cancel() } else { self.receive() }
            }
        }
    }
    func respond(_ code: Int, _ value: [String:Any]) {
        guard !completed else { return }; completed = true
        let body = (try? JSONSerialization.data(withJSONObject:value)) ?? Data("{}".utf8)
        let response = Data("HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        connection.send(content:response,completion:.contentProcessed { [connection] _ in connection.cancel() })
    }
}
