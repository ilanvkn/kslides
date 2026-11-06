import AppKit
import KSlidesCore

extension StudioStore {
    var geometryRoot: URL { root.appendingPathComponent("GeometryJobs",isDirectory:true) }
    var rendererConnected: Bool { geometryWorkerSeen.map { Date().timeIntervalSince($0) < 8 } ?? false }
    func loadGeometryJobs() throws {
        try FileManager.default.createDirectory(at:geometryRoot,withIntermediateDirectories:true)
        let path = geometryRoot.appendingPathComponent("jobs.json")
        if FileManager.default.fileExists(atPath:path.path) {
            geometryJobs = try JSONDecoder().decode([GeometryJob].self,from:Data(contentsOf:path))
            for i in geometryJobs.indices {
                if let slide = lessons.first(where:{ $0.id == geometryJobs[i].lessonID })?.slides.first(where:{ $0.geometryJobID == geometryJobs[i].id }) {
                    geometryJobs[i].state = "applied"; geometryJobs[i].appliedSlideID = slide.id; geometryJobs[i].message = "Added to lesson"
                }
            }
            for i in geometryJobs.indices where geometryJobs[i].state == "running" {
                geometryJobs[i].state = "queued"; geometryJobs[i].lease = nil
                geometryJobs[i].message = "Resuming after restart"
            }
            try saveGeometryJobs(geometryJobs)
        }
    }
    func saveGeometryJobs(_ next: [GeometryJob]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(next).write(to:geometryRoot.appendingPathComponent("jobs.json"),options:.atomic)
        geometryJobs = next
    }
    func geometryJob(_ id: UUID) throws -> GeometryJob {
        guard let job = geometryJobs.first(where: { $0.id == id }) else { throw StudioError.invalid("Render job not found.") }; return job
    }
    func updateGeometryJob(_ value: GeometryJob) throws {
        var copy = value; copy.updatedAt = Date()
        try saveGeometryJobs(geometryJobs.map { $0.id == copy.id ? copy : $0 })
    }
    func enqueueGeometry(lessonID: UUID, slideID: UUID?, expected: Int, scene: GeometryScene, title: String) throws -> GeometryJob {
        let lesson = try lesson(lessonID); _ = try scene.validated()
        guard expected == lesson.revision else { throw StudioError.invalid("Revision conflict. Reload before rendering.") }
        guard !lesson.slides.contains(where: { editorDrafts[$0.id] != nil }) else { throw StudioError.invalid("Save or reload your slide edits before rendering.") }
        guard slideID == nil || lesson.slides.contains(where: { $0.id == slideID }) else { throw StudioError.invalid("Slide not found.") }
        guard slideID != nil || lesson.slides.count < 100 else { throw StudioError.invalid("This lesson has reached its 100-slide limit.") }
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count <= 300 else { throw StudioError.invalid("Give the scene a short title.") }
        if let texture = scene.texture {
            if images[texture] == nil { images[texture] = NSImage(contentsOf:assets.appendingPathComponent(texture)) }
            guard images[texture] != nil else { throw StudioError.invalid("The texture image is missing. Choose it again.") }
        }
        guard geometryJobs.filter({ ["queued","running"].contains($0.state) }).count < 16 else { throw StudioError.invalid("Let some of the queued scenes finish first.") }
        let job = GeometryJob(lessonID:lessonID,slideID:slideID,expectedRevision:expected,scene:scene,title:title)
        try saveGeometryJobs(geometryJobs + [job]); message = "Scene queued for local rendering"
        return job
    }
    func importGeometryTexture(_ data: Data) throws -> String {
        guard data.count <= 15_000_000, let image = NSImage(data:data), let source = NSBitmapImageRep(data:data), source.pixelsWide <= 12000, source.pixelsHigh <= 12000 else { throw StudioError.invalid("Choose an image up to 15 MB and 12,000 pixels per edge.") }
        // Normalize before transferring to the renderer; no external path is executed.
        let longest = max(source.pixelsWide,source.pixelsHigh)
        let factor = min(1,2048.0/Double(longest))
        let width = max(1,Int(Double(source.pixelsWide)*factor)), height = max(1,Int(Double(source.pixelsHigh)*factor))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0), let context = NSGraphicsContext(bitmapImageRep:rep) else { throw StudioError.invalid("Could not prepare this texture.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in:CGRect(x:0,y:0,width:width,height:height)); NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using:.png,properties:[:]) else { throw StudioError.invalid("Could not encode the texture.") }
        let name = "texture-\(UUID().uuidString).png"
        try png.write(to:assets.appendingPathComponent(name),options:.atomic); images[name] = NSImage(data:png)
        return name
    }
    func claimGeometryJob() throws -> Any {
        // A lost worker's lease expires. A late result cannot overwrite its replacement.
        for old in geometryJobs where old.state == "running" && Date().timeIntervalSince(old.updatedAt) > 180 {
            var job = old; job.state = "queued"; job.lease = nil; job.message = "Retrying after a lost rendering connection"; try updateGeometryJob(job)
        }
        guard var job = geometryJobs.first(where: { $0.state == "queued" }) else { return NSNull() }
        job.state = "running"; job.lease = UUID(); job.message = "Rendering \(job.scene.kind.label.lowercased()) locally"
        try updateGeometryJob(job)
        var payload = try JSONSerialization.jsonObject(with:JSONEncoder().encode(job)) as! [String:Any]
        if let texture = job.scene.texture { payload["texture_base64"] = try Data(contentsOf:assets.appendingPathComponent(texture)).base64EncodedString() }
        return payload
    }
    func completeGeometryJob(id: UUID, lease: UUID, image: Data, blend: Data, report: [String:Any]) throws -> GeometryJob {
        var job = try geometryJob(id)
        guard job.state == "running", job.lease == lease else { throw StudioError.invalid("This render was cancelled or its worker lease expired.") }
        guard image.count <= 15_000_000, image.starts(with:[137,80,78,71,13,10,26,10]), let rep = NSBitmapImageRep(data:image), rep.pixelsWide == 900, rep.pixelsHigh == 900, blend.count <= 10_000_000, blend.starts(with:Data("BLENDER".utf8)) else { throw StudioError.invalid("The renderer returned an invalid image or source scene.") }
        guard report["verified"] as? Bool == true, report["kind"] as? String == job.scene.kind.rawValue, let values = report["measurements"] as? [String:Double], Set(values.keys) == Set(job.scene.measurements.keys), job.scene.measurements.allSatisfy({ key,value in values[key].map { $0.isFinite && abs($0-value) <= max(1,abs(value))*1e-9 } ?? false }) else { throw StudioError.invalid("Rendered measurements did not match the requested geometry.") }
        let dir = geometryRoot.appendingPathComponent(id.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try image.write(to:dir.appendingPathComponent("render.png"),options:.atomic)
        try blend.write(to:dir.appendingPathComponent("scene.blend"),options:.atomic)
        try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:dir.appendingPathComponent("verification.json"),options:.atomic)
        job.state = "ready"; job.message = "Render ready"; try updateGeometryJob(job)
        do { _ = try applyGeometryJob(id,expected:job.expectedRevision) }
        catch { job = try geometryJob(id); job.message = "Render preserved. \(error.localizedDescription)"; try updateGeometryJob(job) }
        return try geometryJob(id)
    }
    @discardableResult func applyGeometryJob(_ id: UUID, expected: Int) throws -> Lesson {
        var job = try geometryJob(id)
        var lesson = try lesson(job.lessonID)
        if let applied = lesson.slides.first(where:{ $0.geometryJobID == id }) {
            job.state = "applied"; job.appliedSlideID = applied.id; job.message = "Added to lesson"; try updateGeometryJob(job); return lesson
        }
        guard job.state == "ready" else { throw StudioError.invalid("Only a finished, unapplied scene can be added.") }
        guard lesson.revision == expected else { throw StudioError.invalid("The lesson changed while rendering. Add the finished scene after reloading the current revision.") }
        guard !lesson.slides.contains(where: { editorDrafts[$0.id] != nil }) else { throw StudioError.invalid("Save or reload slide edits before adding the scene.") }
        let index = job.slideID.flatMap { id in lesson.slides.firstIndex { $0.id == id } }
        if job.slideID != nil && index == nil { throw StudioError.invalid("The target slide no longer exists.") }
        var slide = index.map { lesson.slides[$0] } ?? Slide(title:job.title,body:job.scene.kind.is3D ? "Explore the shape from another viewpoint." : "Measure the shape and describe what changes.",studentAction:"Predict what happens when the size doubles.",layout:"geometry")
        slide.title = job.title; slide.layout = "geometry"; slide.geometryScene = job.scene; slide.renderedGeometryScene = job.scene; slide.geometryJobID = id
        let name = "geometry-\(id.uuidString).png", file = assets.appendingPathComponent(name)
        let data = try Data(contentsOf:geometryRoot.appendingPathComponent(id.uuidString).appendingPathComponent("render.png"))
        try data.write(to:file,options:.atomic)
        slide.artwork = name; slide.artworkTextSnapshot = nil
        if let index { lesson.slides[index] = slide } else { lesson.slides.append(slide) }
        let saved: Lesson
        do { saved = try replace(lesson,expected:expected) } catch { try? FileManager.default.removeItem(at:file); throw error }
        images[name] = NSImage(data:data)
        if selectedLessonID == saved.id { selectedSlideID = slide.id }
        job.state = "applied"; job.appliedSlideID = slide.id; job.message = "Added to lesson"; try updateGeometryJob(job)
        return saved
    }
    func geometryRPC(_ name: String, _ a: [String:Any]) throws -> Any {
        func id(_ key: String) throws -> UUID { guard let value = a[key] as? String, let id = UUID(uuidString:value) else { throw StudioError.invalid("Invalid \(key).") }; return id }
        func encoded(_ job: GeometryJob) throws -> Any {
            var value = try JSONSerialization.jsonObject(with:JSONEncoder().encode(job)) as! [String:Any]
            value["measurements"] = job.scene.measurements
            if ["ready","applied"].contains(job.state) {
                let dir = geometryRoot.appendingPathComponent(job.id.uuidString)
                value["artifacts"] = ["render":dir.appendingPathComponent("render.png").path,"source_scene":dir.appendingPathComponent("scene.blend").path,"verification":dir.appendingPathComponent("verification.json").path]
            }
            return value
        }
        switch name {
        case "kslides_geometry_texture":
            guard let text = a["image_base64"] as? String, let data = Data(base64Encoded:text), data.starts(with:[137,80,78,71,13,10,26,10]) || data.starts(with:[255,216,255]) else { throw StudioError.invalid("Provide PNG or JPEG image bytes.") }
            return ["texture":try importGeometryTexture(data)]
        case "_geometry_ping":
            geometryWorkerSeen = Date()
            return try encoded(geometryJob(id("job_id")))
        case "_geometry_next":
            geometryWorkerSeen = Date(); geometryBlenderAvailable = a["available"] as? Bool ?? false
            guard geometryBlenderAvailable else { return NSNull() }
            return try claimGeometryJob()
        case "_geometry_complete":
            guard let text = a["png"] as? String, let image = Data(base64Encoded:text), let source = a["blend"] as? String, let blend = Data(base64Encoded:source), let report = a["report"] as? [String:Any] else { throw StudioError.invalid("Incomplete render result.") }
            return try encoded(completeGeometryJob(id:id("job_id"),lease:id("lease"),image:image,blend:blend,report:report))
        case "_geometry_fail":
            var job = try geometryJob(id("job_id")); guard job.lease == (try id("lease")), job.state == "running" else { return try encoded(job) }
            job.state = "failed"; job.message = String((a["message"] as? String ?? "Rendering failed").prefix(1000)); try updateGeometryJob(job); return try encoded(job)
        case "kslides_geometry_engines": return ["worker_connected":rendererConnected,"blender_available":geometryBlenderAvailable && rendererConnected,"shapes":GeometryKind.allCases.map(\.rawValue),"image_playground":"Use Geometry Lab's Image Playground button on a supported Mac. Availability depends on Apple Intelligence.","execution":"Local NumPy/Blender worker through a live KSlides MCP connection","offline_scope":"Geometry rendering is local; the connected AI conversation may use the network."] as [String:Any]
        case "kslides_render_scene":
            guard let raw = a["scene"] as? [String:Any], Set(raw.keys).isSubset(of:["kind","size","yaw","pitch","unit","texture"]), let kind = GeometryKind(rawValue:raw["kind"] as? String ?? ""), let n = raw["size"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let expected = a["expected_revision"] as? Int else { throw StudioError.invalid("Provide a shape and numeric size in the scene.") }
            var scene = GeometryScene(); scene.kind = kind; scene.size = n.doubleValue
            for key in ["yaw","pitch"] where raw[key] != nil { guard let v = raw[key] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { throw StudioError.invalid("Use a numeric viewpoint.") }; if key == "yaw" { scene.yaw = v.doubleValue } else { scene.pitch = v.doubleValue } }
            if let rawUnit = raw["unit"] { guard let s = rawUnit as? String else { throw StudioError.invalid("Use a text unit.") }; scene.unit = s }
            if let rawTexture = raw["texture"] { guard let s = rawTexture as? String else { throw StudioError.invalid("Use a managed texture filename.") }; scene.texture = s }
            let target = a["slide_id"] != nil ? try id("slide_id") : nil
            return try encoded(enqueueGeometry(lessonID:id("lesson_id"),slideID:target,expected:expected,scene:scene,title:a["title"] as? String ?? kind.label))
        case "kslides_render_job": return try encoded(geometryJob(id("job_id")))
        case "kslides_cancel_render":
            var job = try geometryJob(id("job_id")); guard ["queued","running"].contains(job.state) else { return try encoded(job) }
            job.state = "cancelled"; job.message = "Cancelled"; try updateGeometryJob(job); return try encoded(job)
        case "kslides_apply_scene":
            guard let revision = a["expected_revision"] as? Int else { throw StudioError.invalid("Provide the current revision.") }
            return try JSONSerialization.jsonObject(with:JSONEncoder().encode(applyGeometryJob(id("job_id"),expected:revision)))
        default: throw StudioError.invalid("Unknown geometry action.")
        }
    }
}
