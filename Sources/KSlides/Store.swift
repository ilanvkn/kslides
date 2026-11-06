import AppKit
import Foundation
import Observation
import Darwin
import KSlidesCore

@Observable @MainActor final class StudioStore {
    var lessons: [Lesson] = []
    var selectedLessonID: UUID?
    var selectedSlideID: UUID?
    var message = ""
    var error: String?
    var serverStatus = "Starting agent connection…"
    var inspectorVisible = true
    var images: [String: NSImage] = [:]
    var editorDrafts: [UUID: Slide] = [:]
    var editorRevisions: [UUID: Int] = [:]
    let root: URL
    let assets: URL
    let exports: URL
    var bridge: AgentServer?
    var geometryJobs: [GeometryJob] = []
    var geometryWorkerSeen: Date?
    var geometryBlenderAvailable = false
    @ObservationIgnored private var libraryLock: Int32 = -1
    @ObservationIgnored private var ownsLibraryLock = false
    var active: Lesson? { lessons.first { $0.id == selectedLessonID } }
    var activeHasDraft: Bool { active?.slides.contains { editorDrafts[$0.id] != nil } ?? false }
    var activeIllustratedArtworkNeedsUpdate: Bool { active?.slides.contains { slide in slide.needsIllustratedArtwork || slide.needsGeometryArtwork || (["illustrated","geometry"].contains(slide.layout) && slide.artwork.flatMap { images[$0] } == nil) } ?? false }
    var canTeach: Bool { active?.slides.isEmpty == false && !activeHasDraft && !activeIllustratedArtworkNeedsUpdate }
    var activeSlide: Slide? { active?.slides.first { $0.id == selectedSlideID } }

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KSlides", isDirectory:true)
        assets = root.appendingPathComponent("Assets", isDirectory:true)
        exports = root.appendingPathComponent("Exports", isDirectory:true)
    }
    func start() {
        guard bridge == nil else { return }
        do {
            for dir in [root, assets, exports] { try FileManager.default.createDirectory(at:dir, withIntermediateDirectories:true) }
            libraryLock = Darwin.open(root.appendingPathComponent("library.lock").path, O_CREAT | O_RDWR, 0o600)
            guard libraryLock >= 0, flock(libraryLock, LOCK_EX | LOCK_NB) == 0 else {
                if libraryLock >= 0 { Darwin.close(libraryLock); libraryLock = -1 }
                throw StudioError.invalid("KSlides is already running from another location. Close that copy and reopen this one to keep lesson edits consistent.")
            }
            ownsLibraryLock = true
            let file = root.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath:file.path) {
                lessons = try JSONDecoder().decode([Lesson].self, from:Data(contentsOf:file))
                for lesson in lessons { _ = try lesson.validated() }
            } else {
                var seed = Seed.lesson()
                for (resource, indexes) in [("park-world", [0]), ("cat-sleeps", [1, 2]), ("dog-runs", [3])] {
                    if let source = Bundle.main.url(forResource:resource, withExtension:"png"), let image = NSImage(contentsOf:source) {
                        let name = "sample-\(resource).png"
                        try Data(contentsOf:source).write(to:assets.appendingPathComponent(name), options:.atomic)
                        images[name] = image
                        for index in indexes { seed.slides[index].artwork = name }
                    }
                }
                lessons = [seed]
                try persist(lessons)
            }
            if !lessons.contains(where: { $0.title == "Sentence Explorers · Studio Edition" }) {
                var sample = Seed.lesson(); sample.title = "Sentence Explorers · Studio Edition"
                for (resource,indexes) in [("park-world",[0]),("cat-sleeps",[1,2]),("bird-sings",[5])] {
                    if let source = Bundle.main.url(forResource:resource,withExtension:"png") {
                        let name = "studio-\(resource).png"
                        try Data(contentsOf:source).write(to:assets.appendingPathComponent(name),options:.atomic)
                        for index in indexes { sample.slides[index].artwork = name }
                    }
                }
                lessons.insert(sample,at:0); try persist(lessons)
            }
            for lesson in lessons { for slide in lesson.slides { if let path = slide.artwork { images[path] = NSImage(contentsOf:assets.appendingPathComponent(path)) } } }
            selectedLessonID = lessons.first?.id
            try loadGeometryJobs()
            selectedSlideID = active?.slides.first?.id
            bridge = AgentServer(store:self)
            try bridge?.start()
        } catch { self.error = error.localizedDescription; serverStatus = "Agent connection unavailable" }
    }
    func persist(_ next: [Lesson]) throws {
        guard ownsLibraryLock else { throw StudioError.invalid("This copy cannot save while another KSlides copy owns the library.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(next).write(to:root.appendingPathComponent("library.json"), options:.atomic)
    }
    func create(_ lesson: Lesson) throws -> Lesson {
        _ = try lesson.validated()
        let next = lessons + [lesson]
        try persist(next); lessons = next; select(lesson.id)
        message = "Lesson saved"
        return lesson
    }
    func select(_ id: UUID) { selectedLessonID = id; selectedSlideID = active?.slides.first?.id }
    func lesson(_ id: UUID) throws -> Lesson {
        guard let lesson = lessons.first(where: { $0.id == id }) else { throw StudioError.invalid("Lesson not found.") }
        return lesson
    }
    @discardableResult func replace(_ updated: Lesson, expected: Int) throws -> Lesson {
        let old = try lesson(updated.id)
        guard old.revision == expected else { throw StudioError.invalid("This lesson changed elsewhere (revision \(old.revision)). Reload the current lesson before saving.") }
        var value = try updated.validated(); value.revision = old.revision + 1; value.updatedAt = Date()
        let next = lessons.map { $0.id == value.id ? value : $0 }
        try persist(next); lessons = next; message = "Saved · revision \(value.revision)"
        if selectedLessonID == value.id, !value.slides.contains(where: { $0.id == selectedSlideID }) { selectedSlideID = value.slides.first?.id }
        return value
    }
    func attach(_ data: Data, to id: UUID, slideID: UUID, expected: Int, provenance: String) throws -> Lesson {
        guard data.count <= 15_000_000, let image = NSImage(data:data), let rep = NSBitmapImageRep(data:data), rep.pixelsWide > 0, rep.pixelsHigh > 0, rep.pixelsWide <= 12000, rep.pixelsHigh <= 12000 else { throw StudioError.invalid("Choose a PNG or JPEG image up to 15 MB and 12,000 pixels per edge.") }
        let isPNG = data.starts(with:[137,80,78,71,13,10,26,10])
        let isJPEG = data.starts(with:[255,216,255])
        guard isPNG || isJPEG else { throw StudioError.invalid("Artwork must be PNG or JPEG.") }
        var value = try lesson(id)
        guard value.revision == expected else { throw StudioError.invalid("Revision conflict. Reload before attaching artwork.") }
        guard let index = value.slides.firstIndex(where: { $0.id == slideID }) else { throw StudioError.invalid("Slide not found.") }
        let name = "\(UUID().uuidString).\(isPNG ? "png" : "jpg")"
        let file = assets.appendingPathComponent(name)
        try data.write(to:file, options:.atomic)
        let record: [String:Any] = ["lesson_id":id.uuidString,"slide_id":slideID.uuidString,"provenance":provenance,"created_at":ISO8601DateFormatter().string(from:Date())]
        do {
            try JSONSerialization.data(withJSONObject:record, options:.prettyPrinted).write(to:assets.appendingPathComponent(name+".json"), options:.atomic)
            value.slides[index].artwork = name
            value.slides[index].artworkTextSnapshot = value.slides[index].layout == "illustrated" ? value.slides[index].sourceText : nil
            if value.slides[index].layout == "geometry" { value.slides[index].renderedGeometryScene = nil }
            let saved = try replace(value, expected:expected)
            images[name] = image
            return saved
        } catch { try? FileManager.default.removeItem(at:file); try? FileManager.default.removeItem(at:assets.appendingPathComponent(name+".json")); throw error }
    }
    func copyBrief() {
        guard let value = active else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value.agentBrief(), forType:.string)
        message = "Brief copied. Paste it into Codex or another connected agent."
    }
    func handle(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
    func importPlan(_ plan: [String: Any]) throws -> Lesson {
        guard let summary = plan["project_summary"] as? [String:Any], let outline = plan["slide_outline"] as? [[String:Any]], let title = summary["title"] as? String, !outline.isEmpty else { throw StudioError.invalid("Choose a Lesson World JSON plan with project_summary and slide_outline.") }
        guard let count = summary["number_of_slides"] as? Int, count == outline.count, outline.enumerated().allSatisfy({ ($0.element["slide_number"] as? Int) == $0.offset + 1 }) else { throw StudioError.invalid("Plan slide count or numbering is inconsistent.") }
        let goals = (summary["learning_goals"] as? [[String:Any]] ?? []).compactMap { $0["goal"] as? String }.joined(separator:"\n")
        var value = Lesson(title:title, topic:summary["topic"] as? String ?? title, audience:summary["audience"] as? String ?? "Educators", goals:goals, world:World(rawValue:summary["theme"] as? String ?? "") ?? .explorer)
        var refs: [Int:Int] = [:]
        for (index, raw) in outline.enumerated() {
            guard let slideTitle = raw["title"] as? String else { throw StudioError.invalid("Plan slide \(index + 1) needs a title.") }
            let cue = raw["teacher_cue"] as? [String:Any] ?? [:]
            let note = ["instruction","expected_answer","misconception","success_evidence"].compactMap { key in (cue[key] as? String).map { "\(key.replacingOccurrences(of:"_",with:" ").capitalized): \($0)" } }.joined(separator:"\n")
            value.slides.append(Slide(title:slideTitle, body:(raw["on_slide_text"] as? [String] ?? []).joined(separator:"\n"), phase:raw["phase"] as? String ?? "teach", purpose:raw["purpose"] as? String ?? "", studentAction:raw["student_action"] as? String ?? "", teacherNotes:note, imagePrompt:raw["image_prompt"] as? String ?? "", durationSeconds:raw["duration_seconds"] as? Int ?? 120, layout:raw["layout"] as? String ?? SlideLayout.suggested(for:raw["phase"] as? String ?? "teach").rawValue))
            if let ref = raw["reveal_for"] as? Int { refs[index] = ref }
        }
        for (index, ref) in refs { guard ref > 0, ref <= index else { throw StudioError.invalid("Reveal must target an earlier slide.") }; value.slides[index].revealFor = value.slides[ref - 1].id }
        return try create(value)
    }
}
