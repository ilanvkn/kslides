import AppKit
import KSlidesCore

struct DesignLayer {
    enum Kind { case shape, text, artwork }
    var kind: Kind
    var name: String
    var rect: CGRect
    var color: String = "FFFFFF"
    var geometry: String = "rect"
    var value: String = ""
    var font: String = "AvenirNext-Medium"
    var size: CGFloat = 32
    var center = false
    var cropAnchor: CGFloat = 0.5
    var tracking: CGFloat = 0
}
struct SlideScene {
    var background: String
    var layers: [DesignLayer]
}

@MainActor enum SlideDesign {
    static func scene(_ slide: Slide, lesson: Lesson, hasImage: Bool) -> SlideScene {
        let layout = SlideLayout(rawValue:slide.layout) ?? .split
        if layout == .illustrated, hasImage {
            return SlideScene(background:"FFFFFF",layers:[DesignLayer(kind:.artwork,name:"Complete illustrated slide",rect:CGRect(x:0,y:0,width:1280,height:720))])
        }
        let type = slide.typography.flatMap(TypeStyle.init(rawValue:)) ?? TypeStyle.themeDefault(lesson.world)
        let ink = lesson.world.ink
        let paper = lesson.world.background
        let accent: String
        let secondary: String
        switch lesson.world {
        case .paper: accent = "7646A2"; secondary = "F2BA62"
        case .science: accent = "2153A5"; secondary = "86D9D1"
        case .mystery: accent = "713D40"; secondary = "D8B778"
        case .chalk: accent = "407168"; secondary = "E9B85B"
        default: accent = "245B59"; secondary = "EFA780"
        }
        let light = lesson.world == .chalk ? "284C44" : "FFFDF6"
        let dark = lesson.world == .chalk ? "183B36" : "203B45"
        var layers: [DesignLayer] = []
        var background = paper
        func shape(_ name: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: String, _ geometry: String = "rect") {
            layers.append(DesignLayer(kind:.shape,name:name,rect:CGRect(x:x,y:y,width:w,height:h),color:color,geometry:geometry))
        }
        func text(_ name: String, _ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ size: CGFloat, _ color: String = "", heading: Bool = false, center: Bool = false, font: String? = nil) {
            guard !value.isEmpty else { return }
            layers.append(DesignLayer(kind:.text,name:name,rect:CGRect(x:x,y:y,width:w,height:h),color:color.isEmpty ? ink : color,value:value,font:font ?? (heading ? type.heading : type.body),size:size,center:center))
        }
        func art(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, anchor: CGFloat = 0.5) {
            if hasImage { layers.append(DesignLayer(kind:.artwork,name:"Lesson artwork",rect:CGRect(x:x,y:y,width:w,height:h),cropAnchor:anchor)) }
        }
        func heading(_ width: CGFloat = 1100) { text("Title",slide.title,64,80,width,140,54,heading:true) }
        func blocks(_ max: Int) -> [String] {
            let parts = slide.body.components(separatedBy:"\n\n").filter { !$0.isEmpty }
            guard parts.count > max else { return parts.isEmpty ? [""] : parts }
            return Array(parts.prefix(max-1)) + [parts.dropFirst(max-1).joined(separator:"\n\n")]
        }
        if ![.cover,.spotlight,.reveal,.exit].contains(layout) {
            switch lesson.world {
            case .science:
                for x in stride(from:0.0,through:1280.0,by:80.0) { shape("Lab grid",x,0,1,720,"DFE8EC") }
                for y in stride(from:0.0,through:720.0,by:80.0) { shape("Lab grid",0,y,1280,1,"DFE8EC") }
            case .paper:
                shape("Paper layer",1100,-110,250,250,"D8C6EE","ellipse")
                shape("Paper layer",1160,22,100,100,secondary,"ellipse")
            case .mystery:
                shape("Case-file margin",28,30,3,640,"D8B778")
                shape("Case-file tab",1050,0,150,30,"D8B778")
            case .chalk:
                shape("Chalk rule",30,34,1220,2,"407168")
                shape("Chalk rule",30,675,1220,2,"407168")
            default: break
            }
        }
        switch layout {
        case .geometry:
            guard let geometry = slide.geometryScene else {
                heading(); text("Geometry pending","Create a mathematical scene in Geometry Lab.",64,300,1100,180,36); break
            }
            background = geometry.kind == .cube ? "132341" : "FFF8E8"
            layers = []
            let fg = geometry.kind == .cube ? "FFF8E8" : "132341"
            let bright = geometry.kind == .cube ? "FAD565" : "214FDB"
            text("Lab label","GEOMETRY LAB · \(geometry.kind.is3D ? "3D" : "2D")",60,38,1100,34,22,bright,heading:true)
            if geometry.kind == .cube {
                text("Title",slide.title,60,95,1130,100,58,fg,heading:true,font:"Georgia")
                art(110,205,480,480)
                text("Dimensions",geometry.dimensionLabel,695,250,510,95,32,bright)
                text("Formula",geometry.formula,695,365,510,95,31,fg)
                text("Surface",geometry.secondaryFormula,695,475,510,90,28,fg)
                text("Body",slide.body,695,585,510,85,25,fg)
            } else if geometry.kind == .sphere {
                text("Title",slide.title,60,115,560,180,62,fg,heading:true,font:"Georgia")
                text("Dimensions",geometry.dimensionLabel,60,315,560,95,34,bright)
                text("Formula",geometry.formula,60,430,560,95,31,fg)
                text("Surface",geometry.secondaryFormula,60,535,560,95,28,fg)
                text("Body",slide.body,60,640,1100,65,25,fg)
                art(710,115,500,500)
            } else {
                text("Title",slide.title,60,95,1130,105,58,fg,heading:true,font:"Georgia")
                art(115,220,455,455)
                text("Dimensions",geometry.dimensionLabel,665,235,550,95,34,bright)
                text("Formula",geometry.formula,665,360,550,95,31,fg)
                text("Perimeter",geometry.secondaryFormula,665,470,550,95,28,fg)
                text("Body",slide.body,665,590,550,95,25,fg)
            }
        case .illustrated:
            heading()
            text("Awaiting slide design","Attach a complete illustrated slide to preview this design.",64,300,1100,180,36)
        case .cover:
            background = accent
            art(0,0,1280,720)
            shape("Cover card",48,358,850,298,paper,"roundRect")
            shape("Cover marker",76,382,70,7,accent)
            text("Title",slide.title,78,404,770,150,66,heading:true)
            text("Body",slide.body,80,558,745,92,27)
            text("Audience",lesson.audience,64,44,900,35,22,hasImage ? "203B45" : "FFFFFF",heading:true)
        case .spotlight:
            background = light
            art(0,0,740,720,anchor:1)
            if !hasImage { shape("Observation shape",70,135,540,450,secondary,"ellipse"); text("Look closely","?",240,200,260,260,170,accent,heading:true,center:true) }
            shape("Observation panel",740,0,540,720,accent)
            text("Phase","LOOK • THINK • TALK",788,64,425,44,20,"FFFFFF",heading:true)
            text("Title",slide.title,788,146,425,248,52,"FFFFFF",heading:true)
            text("Body",slide.body,788,418,425,180,30,"FFFFFF")
        case .concept:
            heading()
            let bs = blocks(2)
            if hasImage { art(930,236,290,350,anchor:1) }
            let total: CGFloat = hasImage ? 825 : 1150
            let width = (total - CGFloat(bs.count-1)*28)/CGFloat(bs.count)
            for (i,b) in bs.enumerated() {
                let x = 64 + CGFloat(i)*(width+28)
                shape("Concept card \(i+1)",x,256,width,290,i == 0 ? accent : secondary,"roundRect")
                text("Concept \(i+1)",b,x+30,296,width-60,200,40,i == 0 ? "FFFFFF" : "263B46",heading:true,center:true)
            }
            text("Student action",slide.studentAction,64,600,1130,68,27)
        case .compare:
            heading()
            let bs = blocks(2)
            let width = (1152-CGFloat(bs.count-1)*32)/CGFloat(bs.count)
            for (i,b) in bs.enumerated() {
                let x = 64 + CGFloat(i)*(width+32)
                shape("Comparison card \(i+1)",x,246,width,298,light,"roundRect")
                shape("Option marker \(i+1)",x+28,275,68,68,i == 0 ? accent : (lesson.world == .chalk ? accent : "B05232"),"ellipse")
                text("Option \(i+1)",String(UnicodeScalar(65+i)!),x+28,281,68,58,37,"FFFFFF",heading:true,center:true)
                text("Comparison \(i+1)",b,x+28,366,width-56,150,43,heading:true)
            }
            shape("Discussion ribbon",64,576,1152,88,accent,"roundRect")
            text("Student action",slide.studentAction,92,598,1096,62,27,"FFFFFF")
        case .steps:
            heading(hasImage ? 920 : 1100)
            art(1044,60,170,150,anchor:1)
            let bs = blocks(3)
            let width = (1152-CGFloat(bs.count-1)*24)/CGFloat(bs.count)
            for (i,b) in bs.enumerated() {
                let x = 64 + CGFloat(i)*(width+24)
                shape("Sequence card \(i+1)",x,252,width,320,light,"roundRect")
                shape("Step tab \(i+1)",x,252,width,8,i == 1 ? secondary : accent)
                text("Step number \(i+1)",String(format:"%02d",i+1),x+26,280,width-52,70,50,accent,heading:true)
                text("Step \(i+1)",b,x+26,380,width-52,155,31)
            }
            text("Student action",slide.studentAction,64,612,1152,60,27)
        case .challenge:
            background = lesson.world == .chalk ? dark : "F6C66E"
            shape("Challenge mark",882,60,320,320,accent,"ellipse")
            text("Challenge symbol","?",882,82,320,300,190,"FFFFFF",heading:true,center:true)
            text("Title",slide.title,64,112,770,204,67,heading:true)
            shape("Task panel",64,348,1152,270,light,"roundRect")
            text("Body",slide.body,102,388,1076,195,36)
        case .reveal:
            background = dark
            shape("Celebration disk",890,90,290,290,secondary,"ellipse")
            if hasImage { art(876,100,320,320,anchor:1) }
            text("Phase","LET’S CHECK",64,52,770,45,20,"86D9D1",heading:true)
            text("Title",slide.title,64,124,780,164,56,"FFFFFF",heading:true)
            shape("Answer panel",64,332,1152,278,paper,"roundRect")
            text("Body",slide.body,102,373,1070,205,43,heading:true)
        case .workshop:
            heading(750)
            shape("Notebook",646,220,570,430,light,"roundRect")
            shape("Notebook margin",695,246,3,378,"EFA780")
            for y in stride(from:304.0,through:594.0,by:58.0) { shape("Writing line",720,y,453,2,lesson.world == .chalk ? secondary : "D6E2DF") }
            text("Notebook label","MY SENTENCE",720,246,455,40,20,accent,heading:true)
            text("Body",slide.body,64,254,526,282,36)
            text("Student action",slide.studentAction,64,558,526,115,25)
        case .exit:
            background = dark
            shape("Ticket",112,76,1056,566,paper,"roundRect")
            shape("Ticket stripe",112,76,1056,14,accent)
            text("Phase","BEFORE YOU GO",166,115,840,34,19,accent,heading:true)
            text("Title",slide.title,166,177,950,150,62,heading:true)
            text("Body",slide.body,166,353,950,151,34)
            shape("Response line",166,557,950,2,accent)
        case .center:
            shape("Idea halo",355,50,570,570,light,"ellipse")
            text("Title",slide.title,110,165,1060,205,72,heading:true,center:true)
            text("Body",slide.body,170,405,940,216,34,center:true)
        case .full:
            art(0,0,1280,720)
            shape("Caption panel",48,394,1184,278,paper,"roundRect")
            text("Title",slide.title,80,420,1116,113,50,heading:true)
            text("Body",slide.body,80,548,1116,103,30)
        case .split:
            art(710,0,570,720,anchor:1)
            shape("Editorial rule",64,128,68,7,accent)
            text("Title",slide.title,64,176,590,195,56,heading:true)
            text("Body",slide.body,64,406,590,210,32)
            if !hasImage { shape("Editorial accent",832,136,320,432,accent,"roundRect"); text("Phase",slide.phase.uppercased(),854,290,276,142,32,"FFFFFF",heading:true,center:true) }
        }
        let footerColor = [.spotlight,.reveal,.exit].contains(layout) || (layout == .geometry && slide.geometryScene?.kind == .cube) ? "FFFFFF" : ink
        if layout != .cover && layout != .spotlight {
            text("Lesson footer",lesson.title.uppercased(),64,686,860,25,13,footerColor,font:"AvenirNext-DemiBold")
            if let index = lesson.slides.firstIndex(where: { $0.id == slide.id }) { text("Page number",String(format:"%02d",index+1),1150,682,64,30,16,footerColor,center:true,font:"AvenirNext-DemiBold") }
        }
        return SlideScene(background:background,layers:layers)
    }
    static func font(_ layer: DesignLayer) -> NSFont { NSFont(name:layer.font,size:layer.size) ?? NSFont.systemFont(ofSize:layer.size) }
    static func attributes(_ layer: DesignLayer) -> [NSAttributedString.Key:Any] {
        let p = NSMutableParagraphStyle(); p.lineSpacing = 6; p.alignment = layer.center ? .center : .left
        return [.font:font(layer),.foregroundColor:NSColor(hex:layer.color),.paragraphStyle:p]
    }
    static func sourceRect(_ image: NSImage, layer: DesignLayer) -> CGRect {
        let ratio = layer.rect.width/layer.rect.height
        var source = CGRect(origin:.zero,size:image.size)
        if image.size.width/image.size.height > ratio { source.size.width = source.height*ratio; source.origin.x = (image.size.width-source.width)*layer.cropAnchor }
        else { source.size.height = source.width/ratio; source.origin.y = (image.size.height-source.height)/2 }
        return source
    }
}
