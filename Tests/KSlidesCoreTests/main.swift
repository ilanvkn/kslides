import Foundation
import KSlidesCore

final class ModelsTests {
    func testGeometryParametersAndStaleRender() throws {
        var scene = GeometryScene(); scene.kind = .cube; scene.size = 3
        XCTAssertEqual(scene.measurements["volume"],27)
        XCTAssertEqual(scene.measurements["surface_area"],54)
        scene.size = 2.5; XCTAssertTrue(scene.formula.contains("≈"))
        scene.size = 0.05; XCTAssertTrue(scene.formula.contains("0.000125"))
        scene.size = 3
        XCTAssertNoThrow(try scene.validated())
        var bad = scene; bad.size = 0; XCTAssertThrowsError(try bad.validated())
        bad.size = .nan; XCTAssertThrowsError(try bad.validated())
        bad = scene; bad.texture = "../outside.png"; XCTAssertThrowsError(try bad.validated())
        var slide = Slide(title:"Cube",layout:"geometry")
        slide.geometryScene = scene; slide.renderedGeometryScene = scene; slide.artwork = "cube.png"
        XCTAssertFalse(slide.needsGeometryArtwork)
        slide.title = "A new teaching question"; XCTAssertFalse(slide.needsGeometryArtwork)
        slide.geometryScene?.size = 4; XCTAssertTrue(slide.needsGeometryArtwork)
        slide.geometryScene = scene
        let lesson = Lesson(title:"Geometry",topic:"Volume",audience:"Upper primary",slides:[slide])
        let decoded = try JSONDecoder().decode(Lesson.self,from:JSONEncoder().encode(lesson))
        XCTAssertEqual(decoded.slides[0].geometryScene,scene)
        XCTAssertTrue(try lesson.copyWithoutArtwork().slides[0].needsGeometryArtwork)
    }
    func testSeedHasCompletePacingAndEarlierReveal() throws {
        let lesson = Seed.lesson()
        XCTAssertEqual(lesson.slides.count,8)
        XCTAssertEqual(lesson.slides.reduce(0) { $0+$1.durationSeconds },1200)
        XCTAssertNoThrow(try lesson.validated())
        XCTAssertEqual(lesson.slides[5].revealFor,lesson.slides[4].id)
        XCTAssertFalse(lesson.slides[4].body.contains("Answer B"))
        XCTAssertTrue(lesson.slides[4].teacherNotes.contains("Answer B"))
    }
    func testRejectsTraversalArtworkAndDuplicateIDs() {
        var lesson = Seed.lesson()
        lesson.slides[0].artwork = "../../secrets.png"
        XCTAssertThrowsError(try lesson.validated())
        lesson.slides[0].artwork = nil
        lesson.slides[1].id = lesson.slides[0].id
        XCTAssertThrowsError(try lesson.validated())
    }
    func testRejectsForwardReveal() {
        var lesson = Seed.lesson()
        lesson.slides[0].revealFor = lesson.slides[1].id
        XCTAssertThrowsError(try lesson.validated())
    }
    func testRoundTripPreservesTeacherAndStudentSeparation() throws {
        let seed = Seed.lesson()
        let decoded = try JSONDecoder().decode(Lesson.self,from:JSONEncoder().encode(seed))
        XCTAssertEqual(seed,decoded)
        XCTAssertTrue(decoded.slides[4].teacherNotes.contains("Answer B"))
        XCTAssertFalse(decoded.slides[4].body.contains("Answer B"))
    }
    func testCatalogHasDistinctToolsAndRevisionProtectedWrites() {
        let tools = ToolCatalog.tools()
        XCTAssertEqual(tools.count,19)
        XCTAssertEqual(Set(ToolCatalog.names).count,tools.count)
        for name in ["kslides_update_lesson","kslides_upsert_slide","kslides_reorder_slides","kslides_attach_artwork","kslides_render_scene","kslides_apply_scene"] {
            let tool = tools.first { $0["name"] as? String == name }!
            let schema = tool["inputSchema"] as! [String:Any]
            XCTAssertTrue((schema["required"] as! [String]).contains("expected_revision"))
        }
    }
    func testSourceCopyRemapsSlideAndRevealIdentity() throws {
        let source = Seed.lesson()
        let copy = try source.copyWithoutArtwork()
        XCTAssertFalse(copy.id == source.id)
        XCTAssertTrue(Set(copy.slides.map(\.id)).isDisjoint(with: Set(source.slides.map(\.id))))
        XCTAssertEqual(copy.slides[5].revealFor,copy.slides[4].id)
        XCTAssertEqual(copy.slides[4].teacherNotes,source.slides[4].teacherNotes)
        XCTAssertNoThrow(try copy.validated())
    }
    func testVariedDesignsAndLegacyDecoding() throws {
        let seed = Seed.lesson()
        XCTAssertEqual(Set(seed.slides.map(\.layout)).count,8)
        XCTAssertEqual(Set(TypeStyle.allCases.map(\.heading)).count,5)
        XCTAssertEqual(SlideLayout.allCases.count,14)
        var raw = try JSONSerialization.jsonObject(with:JSONEncoder().encode(seed)) as! [String:Any]
        var slides = raw["slides"] as! [[String:Any]]
        slides[0].removeValue(forKey:"typography"); slides[0]["layout"] = "full"; raw["slides"] = slides
        let legacy = try JSONDecoder().decode(Lesson.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertEqual(legacy.slides[0].typography,nil)
        XCTAssertNoThrow(try legacy.validated())
        var invalid = seed; invalid.slides[0].typography = "unknown"
        XCTAssertThrowsError(try invalid.validated())
    }
    func testZIPKnownCRCAndHeader() {
        XCTAssertEqual(StoredZIP.crc32(Data("123456789".utf8)),0xcbf43926)
        let archive = StoredZIP.archive([("hello.txt",Data("hello".utf8))])
        XCTAssertEqual(Array(archive.prefix(4)),[0x50,0x4b,0x03,0x04])
        XCTAssertEqual(Array(archive.suffix(22).prefix(4)),[0x50,0x4b,0x05,0x06])
    }
    func testIllustratedWordsAndPrivateNotes() throws {
        var slide = Slide(title:"Sentence Safari",body:"The cat sleeps.",teacherNotes:"PRIVATE ANSWER",layout:"illustrated")
        XCTAssertTrue(slide.needsIllustratedArtwork)
        slide.artwork = "slide.png"; slide.artworkTextSnapshot = slide.sourceText
        XCTAssertFalse(slide.needsIllustratedArtwork)
        slide.teacherNotes = "CHANGED PRIVATE ANSWER"
        XCTAssertFalse(slide.needsIllustratedArtwork)
        let lesson = Lesson(title:"Preview",topic:"Sentences",audience:"Year 2",slides:[slide])
        let decoded = try JSONDecoder().decode(Lesson.self,from:JSONEncoder().encode(lesson))
        XCTAssertFalse(decoded.slides[0].needsIllustratedArtwork)
        XCTAssertFalse(lesson.prompt(for:slide).contains("PRIVATE ANSWER"))
        slide.body = "The cat runs."
        XCTAssertTrue(slide.needsIllustratedArtwork)
        slide.body = "The cat sleeps."
        XCTAssertFalse(slide.needsIllustratedArtwork)
        let copy = try lesson.copyWithoutArtwork()
        XCTAssertTrue(copy.slides[0].needsIllustratedArtwork)
        XCTAssertEqual(copy.slides[0].artworkTextSnapshot,nil)
    }
}

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected equal values") }
func XCTAssertTrue(_ value: Bool) { precondition(value, "Expected true") }
func XCTAssertFalse(_ value: Bool) { precondition(!value, "Expected false") }
func XCTAssertNoThrow<T>(_ work: @autoclosure () throws -> T) { do { _ = try work() } catch { preconditionFailure("Unexpected error: \(error)") } }
func XCTAssertThrowsError<T>(_ work: @autoclosure () throws -> T) { var threw = false; do { _ = try work() } catch { threw = true }; precondition(threw, "Expected validation error") }
let tests = ModelsTests()
try tests.testSeedHasCompletePacingAndEarlierReveal()
tests.testRejectsTraversalArtworkAndDuplicateIDs()
tests.testRejectsForwardReveal()
try tests.testRoundTripPreservesTeacherAndStudentSeparation()
tests.testCatalogHasDistinctToolsAndRevisionProtectedWrites()
tests.testZIPKnownCRCAndHeader()
try tests.testSourceCopyRemapsSlideAndRevealIdentity()
try tests.testVariedDesignsAndLegacyDecoding()
try tests.testIllustratedWordsAndPrivateNotes()
try tests.testGeometryParametersAndStaleRender()
print("PASS: 10 KSlides domain, geometry, tool-contract and ZIP checks")
