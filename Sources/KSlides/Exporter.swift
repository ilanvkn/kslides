import AppKit
import Foundation
import KSlidesCore

extension NSColor {
    convenience init(hex: String) {
        let n = UInt32(hex,radix:16) ?? 0
        self.init(srgbRed:CGFloat((n >> 16) & 255)/255,green:CGFloat((n >> 8) & 255)/255,blue:CGFloat(n & 255)/255,alpha:1)
    }
}
@MainActor enum SlideDrawing {
    static let size = CGSize(width:1280,height:720)
    static func fitIssue(_ slide: Slide, lesson: Lesson? = nil) -> String? {
        if slide.needsGeometryArtwork { return "Render this geometry scene before teaching or exporting." }
        if slide.layout == "illustrated", slide.artwork != nil, slide.needsIllustratedArtwork { return "Source words changed. Regenerate and attach the illustrated slide before teaching or exporting." }
        let value = lesson ?? Lesson(title:"Lesson",topic:"",audience:"",slides:[slide])
        let scene = SlideDesign.scene(slide,lesson:value,hasImage:slide.artwork != nil)
        for layer in scene.layers where layer.kind == .text {
            let measured = (layer.value as NSString).boundingRect(with:CGSize(width:layer.rect.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:SlideDesign.attributes(layer))
            if measured.height > layer.rect.height + 2 { return "\(layer.name) needs more space in this design. Shorten it, split the slide, or choose another composition." }
        }
        return nil
    }
    static func draw(_ slide: Slide, lesson: Lesson, image: NSImage?, context: CGContext) {
        context.saveGState(); NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        let scene = SlideDesign.scene(slide,lesson:lesson,hasImage:image != nil)
        NSColor(hex:scene.background).setFill(); CGRect(origin:.zero,size:size).fill()
        for layer in scene.layers {
            let rect = CGRect(x:layer.rect.minX,y:720-layer.rect.maxY,width:layer.rect.width,height:layer.rect.height)
            switch layer.kind {
            case .shape:
                NSColor(hex:layer.color).setFill()
                if layer.geometry == "ellipse" { NSBezierPath(ovalIn:rect).fill() }
                else if layer.geometry == "roundRect" { NSBezierPath(roundedRect:rect,xRadius:20,yRadius:20).fill() }
                else { rect.fill() }
            case .text: (layer.value as NSString).draw(in:rect,withAttributes:SlideDesign.attributes(layer))
            case .artwork:
                if let image { image.draw(in:rect,from:SlideDesign.sourceRect(image,layer:layer),operation:.sourceOver,fraction:1) }
            }
        }
        NSGraphicsContext.restoreGraphicsState(); context.restoreGState()
    }
    static func png(_ slide: Slide, lesson: Lesson, image: NSImage?) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1920,pixelsHigh:1080,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0), let context = NSGraphicsContext(bitmapImageRep:rep)?.cgContext else { throw StudioError.invalid("Image renderer unavailable.") }
        context.scaleBy(x:1.5,y:1.5)
        draw(slide,lesson:lesson,image:image,context:context)
        guard let data = rep.representation(using:.png,properties:[:]) else { throw StudioError.invalid("Could not encode slide image.") }
        return data
    }
}

@MainActor enum Exporter {
    static func export(_ lesson: Lesson, format: String, store: StudioStore) throws -> [URL] {
        guard !lesson.slides.isEmpty else { throw StudioError.invalid("Add a slide before exporting.") }
        _ = try lesson.validated()
        let exportSlides = format == "worksheet" ? lesson.slides.filter { $0.revealFor == nil && $0.phase != "reveal" } : lesson.slides
        guard !exportSlides.isEmpty else { throw StudioError.invalid("This lesson has no student slides to export.") }
        for (index,slide) in exportSlides.enumerated() {
            if slide.layout == "illustrated", slide.artwork == nil, format != "json" { throw StudioError.invalid("Slide \(index + 1) needs its complete illustrated artwork before exporting.") }
            if let issue = SlideDrawing.fitIssue(slide,lesson:lesson), format != "json" { throw StudioError.invalid("Slide \(index + 1): \(issue)") }
            if let filename = slide.artwork, store.images[filename] == nil { throw StudioError.invalid("Slide \(index + 1) is missing its artwork. Attach the image again before exporting.") }
        }
        let dir = store.exports.appendingPathComponent("\(lesson.id.uuidString)-r\(lesson.revision)-\(UUID().uuidString.prefix(8))",isDirectory:true)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let basename = "lesson"
        let file = dir.appendingPathComponent(basename+"."+(format == "worksheet" ? "pdf" : format))
        switch format {
        case "json": let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(lesson).write(to:file,options:.atomic)
        case "png":
            var paths: [URL] = []
            for (i,slide) in lesson.slides.enumerated() { let path = dir.appendingPathComponent(String(format:"slide-%02d.png",i+1)); try SlideDrawing.png(slide,lesson:lesson,image:slide.artwork.flatMap { store.images[$0] }).write(to:path,options:.atomic); paths.append(path) }
            return paths
        case "pdf", "worksheet":
            let bytes = NSMutableData()
            guard let consumer = CGDataConsumer(data:bytes) else { throw StudioError.invalid("PDF renderer unavailable.") }
            var bounds = format == "worksheet" ? CGRect(x:0,y:0,width:595,height:842) : CGRect(origin:.zero,size:SlideDrawing.size)
            guard let context = CGContext(consumer:consumer,mediaBox:&bounds,nil) else { throw StudioError.invalid("PDF renderer unavailable.") }
            for slide in exportSlides {
                context.beginPDFPage(nil)
                if format == "worksheet" {
                    context.saveGState(); context.translateBy(x:30,y:472); context.scaleBy(x:535/1280,y:535/1280)
                    SlideDrawing.draw(slide,lesson:lesson,image:slide.artwork.flatMap { store.images[$0] },context:context); context.restoreGState()
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
                    let instructions = slide.studentAction + "\n\nName: ____________________    Date: ______________\n\nMy response:"
                    (instructions as NSString).draw(in:CGRect(x:38,y:320,width:520,height:125),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.black])
                    NSGraphicsContext.restoreGraphicsState()
                    context.setStrokeColor(NSColor.lightGray.cgColor); context.setLineWidth(0.6)
                    for y in stride(from:80,through:295,by:35) { context.move(to:CGPoint(x:38,y:y)); context.addLine(to:CGPoint(x:557,y:y)); context.strokePath() }
                } else { SlideDrawing.draw(slide,lesson:lesson,image:slide.artwork.flatMap { store.images[$0] },context:context) }
                context.endPDFPage()
            }
            context.closePDF(); try (bytes as Data).write(to:file,options:.atomic)
        case "pptx": try PowerPoint.make(lesson,assets:store.assets).write(to:file,options:.atomic)
        default: throw StudioError.invalid("Unsupported export format.")
        }
        return [file]
    }
}

@MainActor enum PowerPoint {
    static let p = "http://schemas.openxmlformats.org/presentationml/2006/main"
    static let a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    static let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let rel = "http://schemas.openxmlformats.org/package/2006/relationships"
    static func esc(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
    static var group: String { "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>" }
    static func relations(_ entries: [(String,String,String)]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"\(rel)\">" + entries.map { "<Relationship Id=\"\($0.0)\" Type=\"\(r)/\($0.1)\" Target=\"\(esc($0.2))\"/>" }.joined() + "</Relationships>"
    }
    static func text(_ id: Int, _ name: String, _ text: String, x: Int, y: Int, w: Int, h: Int, size: Int, color: String, bold: Bool = false, placeholder: String = "", alignment: String = "l", font: String = "Arial") -> String {
        let paragraphs = text.components(separatedBy:"\n").map { "<a:p><a:pPr algn=\"\(alignment)\"><a:lnSpc><a:spcPct val=\"110000\"/></a:lnSpc></a:pPr><a:r><a:rPr lang=\"en-US\" sz=\"\(size)\" b=\"\(bold ? 1 : 0)\"><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:latin typeface=\"\(esc(font))\"/><a:ea typeface=\"\(esc(font))\"/><a:cs typeface=\"\(esc(font))\"/></a:rPr><a:t xml:space=\"preserve\">\(esc($0))</a:t></a:r><a:endParaRPr lang=\"en-US\"/></a:p>" }.joined()
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr>\(placeholder)</p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>"
    }
    static func make(_ lesson: Lesson, assets: URL) throws -> Data {
        var files: [(String,Data)] = []
        func add(_ name: String, _ value: String) { files.append((name,Data(value.utf8))) }
        let contentType = "application/vnd.openxmlformats-officedocument.presentationml."
        var overrides = "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"\(contentType)presentation.main+xml\"/><Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"\(contentType)slideMaster+xml\"/><Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"\(contentType)slideLayout+xml\"/><Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/><Override PartName=\"/ppt/notesMasters/notesMaster1.xml\" ContentType=\"\(contentType)notesMaster+xml\"/>"
        var presentationRels: [(String,String,String)] = [("rId1","slideMaster","slideMasters/slideMaster1.xml"),("rId2","notesMaster","notesMasters/notesMaster1.xml")]
        var ids = ""
        for (i,slide) in lesson.slides.enumerated() {
            let n = i+1
            overrides += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"\(contentType)slide+xml\"/><Override PartName=\"/ppt/notesSlides/notesSlide\(n).xml\" ContentType=\"\(contentType)notesSlide+xml\"/>"
            ids += "<p:sldId id=\"\(255+n)\" r:id=\"rId\(n+2)\"/>"
            presentationRels.append(("rId\(n+2)","slide","slides/slide\(n).xml"))
            var shapes = ""
            var slideRels: [(String,String,String)] = [("rId1","slideLayout","../slideLayouts/slideLayout1.xml"),("rId2","notesSlide","../notesSlides/notesSlide\(n).xml")]
            let scene = SlideDesign.scene(slide,lesson:lesson,hasImage:slide.artwork != nil)
            var artworkData: Data?
            if let filename = slide.artwork {
                artworkData = try Data(contentsOf:assets.appendingPathComponent(filename))
                let ext = URL(fileURLWithPath:filename).pathExtension
                files.append(("ppt/media/image\(n).\(ext)",artworkData!))
                slideRels.append(("rId3","image","../media/image\(n).\(ext)"))
            }
            func emu(_ n: CGFloat) -> Int { Int((n*9525).rounded()) }
            for (index,layer) in scene.layers.enumerated() {
                let id = index+2
                let x = emu(layer.rect.minX), y = emu(layer.rect.minY), w = emu(layer.rect.width), h = emu(layer.rect.height)
                let adjust = layer.geometry == "roundRect" ? "<a:gd name=\"adj\" fmla=\"val \(Int(min(50000,20/min(layer.rect.width,layer.rect.height)*100000)))\"/>" : ""
                switch layer.kind {
                case .text:
                    let face = SlideDesign.font(layer).familyName ?? "Arial"
                    shapes += text(id,esc(layer.name),layer.value,x:x,y:y,w:w,h:h,size:Int(layer.size*75),color:layer.color,bold:layer.font.contains("Bold") || layer.font.contains("Heavy"),alignment:layer.center ? "ctr" : "l",font:face)
                case .shape:
                    shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(esc(layer.name))\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm><a:prstGeom prst=\"\(layer.geometry)\"><a:avLst>\(adjust)</a:avLst></a:prstGeom><a:solidFill><a:srgbClr val=\"\(layer.color)\"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"
                case .artwork:
                    guard let data = artworkData, let image = NSImage(data:data) else { continue }
                    let source = SlideDesign.sourceRect(image,layer:layer)
                    let left = Int(source.minX/image.size.width*100000), right = Int((image.size.width-source.maxX)/image.size.width*100000)
                    let top = Int((image.size.height-source.maxY)/image.size.height*100000), bottom = Int(source.minY/image.size.height*100000)
                    shapes += "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Lesson artwork\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId3\"/><a:srcRect l=\"\(left)\" t=\"\(top)\" r=\"\(right)\" b=\"\(bottom)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
                }
            }
            add("ppt/slides/slide\(n).xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sld xmlns:p=\"\(p)\" xmlns:a=\"\(a)\" xmlns:r=\"\(r)\"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"\(scene.background)\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>\(group)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>")
            add("ppt/slides/_rels/slide\(n).xml.rels",relations(slideRels))
            let note = "Purpose: \(slide.purpose)\nStudent action: \(slide.studentAction)\nDuration: \(slide.durationSeconds) seconds\n\n\(slide.teacherNotes)"
            let body = text(2,"Teacher notes",note,x:0,y:0,w:6858000,h:9144000,size:1400,color:"263B46",placeholder:"<p:ph type=\"body\" idx=\"1\"/>")
            add("ppt/notesSlides/notesSlide\(n).xml","<p:notes xmlns:p=\"\(p)\" xmlns:a=\"\(a)\" xmlns:r=\"\(r)\"><p:cSld><p:spTree>\(group)\(body)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>")
            add("ppt/notesSlides/_rels/notesSlide\(n).xml.rels",relations([("rId1","notesMaster","../notesMasters/notesMaster1.xml"),("rId2","slide","../slides/slide\(n).xml")]))
        }
        add("[Content_Types].xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>\(overrides)</Types>")
        add("_rels/.rels",relations([("rId1","officeDocument","ppt/presentation.xml")]))
        add("ppt/presentation.xml","<p:presentation xmlns:p=\"\(p)\" xmlns:a=\"\(a)\" xmlns:r=\"\(r)\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:notesMasterIdLst><p:notesMasterId r:id=\"rId2\"/></p:notesMasterIdLst><p:sldIdLst>\(ids)</p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\" type=\"screen16x9\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>")
        add("ppt/_rels/presentation.xml.rels",relations(presentationRels))
        let cmap = "<p:clrMap accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" bg1=\"lt1\" bg2=\"lt2\" folHlink=\"folHlink\" hlink=\"hlink\" tx1=\"dk1\" tx2=\"dk2\"/>"
        add("ppt/slideMasters/slideMaster1.xml","<p:sldMaster xmlns:p=\"\(p)\" xmlns:a=\"\(a)\" xmlns:r=\"\(r)\"><p:cSld><p:spTree>\(group)</p:spTree></p:cSld>\(cmap)<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>")
        add("ppt/slideMasters/_rels/slideMaster1.xml.rels",relations([("rId1","slideLayout","../slideLayouts/slideLayout1.xml"),("rId2","theme","../theme/theme1.xml")]))
        add("ppt/slideLayouts/slideLayout1.xml","<p:sldLayout xmlns:p=\"\(p)\" xmlns:a=\"\(a)\" type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>\(group)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>")
        add("ppt/slideLayouts/_rels/slideLayout1.xml.rels",relations([("rId1","slideMaster","../slideMasters/slideMaster1.xml")]))
        add("ppt/notesMasters/notesMaster1.xml","<p:notesMaster xmlns:p=\"\(p)\" xmlns:a=\"\(a)\"><p:cSld><p:spTree>\(group)</p:spTree></p:cSld>\(cmap)<p:notesStyle/></p:notesMaster>")
        add("ppt/notesMasters/_rels/notesMaster1.xml.rels",relations([("rId1","theme","../theme/theme1.xml")]))
        let scheme = [("dk1","263B46"),("lt1","FFFFFF"),("dk2","245B59"),("lt2","F7EAD1"),("accent1","245B59"),("accent2","D66B45"),("accent3","47765C"),("accent4","E9B85B"),("accent5","394B56"),("accent6","596B50"),("hlink","0563C1"),("folHlink","954F72")].map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"9525\">\(fill)<a:prstDash val=\"solid\"/></a:ln>"
        add("ppt/theme/theme1.xml","<a:theme xmlns:a=\"\(a)\" name=\"KSlides\"><a:themeElements><a:clrScheme name=\"KSlides\">\(scheme)</a:clrScheme><a:fontScheme name=\"KSlides\"><a:majorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme><a:fmtScheme name=\"KSlides\"><a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst><a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>")
        return StoredZIP.archive(files)
    }
}
