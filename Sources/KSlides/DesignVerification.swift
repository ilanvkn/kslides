import AppKit
import Foundation
import KSlidesCore

@MainActor enum DesignVerification {
    static func run(root: URL) throws {
        let output = root.appendingPathComponent("output/design-lab")
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var report: [[String:Any]] = []
        let image = NSImage(contentsOf:root.appendingPathComponent("Resources/park-world.png"))
        for world in World.allCases {
            let slug = world.rawValue.lowercased().replacingOccurrences(of:" ",with:"-")
            var lesson = Lesson(title:world.rawValue,topic:"Complete sentences",audience:"Year 2 • English",world:world)
            for layout in SlideLayout.allCases where layout != .illustrated && layout != .geometry {
                var slide = Slide(title:layout.label,body:"A sentence tells a complete idea.",studentAction:"Say one complete sentence.",layout:layout.rawValue)
                if [.concept,.compare].contains(layout) { slide.body = "Who?\nThe cat\n\nAction?\nsleeps" }
                if layout == .steps { slide.body = "Name who\nThe dog\n\nAdd an action\nruns\n\nSay it together\nThe dog runs." }
                if layout == .workshop { slide.body = "Choose an animal.\nSay your idea.\nWrite a sentence." }
                if layout == .reveal { slide.body = "The bird sings.\n\nWho + an action." }
                if [.cover,.spotlight,.full,.split].contains(layout) { slide.artwork = "park-world.png" }
                lesson.slides.append(slide)
            }
            _ = try lesson.validated()
            for slide in lesson.slides {
                if let issue = SlideDrawing.fitIssue(slide,lesson:lesson) { throw StudioError.invalid("\(world.rawValue)/\(slide.layout): \(issue)") }
                let png = try SlideDrawing.png(slide,lesson:lesson,image:slide.artwork != nil ? image : nil)
                let path = output.appendingPathComponent("\(slug)-\(slide.layout).png")
                try png.write(to:path)
                let scene = SlideDesign.scene(slide,lesson:lesson,hasImage:slide.artwork != nil)
                for layer in scene.layers where layer.kind == .text { guard NSFont(name:layer.font,size:layer.size) != nil else { throw StudioError.invalid("Missing font \(layer.font)") } }
                report.append(["world":world.rawValue,"layout":slide.layout,"path":path.path,"layers":scene.layers.count,"text_fit":"passed"])
            }
            try PowerPoint.make(lesson,assets:root.appendingPathComponent("Resources")).write(to:output.appendingPathComponent("\(slug).pptx"))
        }
        let sample = Seed.lesson()
        for slide in sample.slides { if let issue = SlideDrawing.fitIssue(slide,lesson:sample) { throw StudioError.invalid("Sample \(slide.title): \(issue)") } }
        var stress = sample.slides[2]; stress.body = String(repeating:"A long teaching statement that needs another slide.\n",count:80)
        guard SlideDrawing.fitIssue(stress,lesson:sample) != nil else { throw StudioError.invalid("Long-content check failed") }
        for type in TypeStyle.allCases {
            for name in [type.heading,type.body] { guard NSFont(name:name,size:32) != nil else { throw StudioError.invalid("Missing typeface \(name)") } }
        }
        try JSONSerialization.data(withJSONObject:["checks":report,"compositions":12,"worlds":6,"native_fonts":5,"long_content":"rejected","sample_text_fit":"passed"],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("docs/revision-02/design-check-report.json"))
        print("PASS: 72 native layout/world renders, 6 editable PowerPoint decks, 5 installed font families, sample text fit and overflow rejection")
    }
}
