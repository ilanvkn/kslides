import SwiftUI
import ImagePlayground
import UniformTypeIdentifiers
import KSlidesCore

struct GeometryLab: View {
    @Bindable var store: StudioStore
    let lessonID: UUID
    let targetSlideID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var scene: GeometryScene
    @State private var title: String
    @State private var replaceSelected: Bool
    @State private var importing = false
    @State private var playground = false
    @State private var localError: String?
    @State private var clock = Date()
    init(store: StudioStore, lesson: Lesson) {
        self.store = store; lessonID = lesson.id; targetSlideID = store.activeSlide?.id
        _scene = State(initialValue:store.activeSlide?.geometryScene ?? GeometryScene())
        _title = State(initialValue:store.activeSlide?.geometryScene != nil ? store.activeSlide!.title : "Explore a sphere")
        _replaceSelected = State(initialValue:store.activeSlide?.geometryScene != nil)
    }
    var jobs: [GeometryJob] { store.geometryJobs.filter { $0.lessonID == lessonID }.reversed().prefix(8).map { $0 } }
    var connected: Bool { _ = clock; return store.rendererConnected && store.geometryBlenderAvailable }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("Geometry Lab").font(.system(size:30,weight:.semibold,design:.serif))
                    Text("Shape, measure, rotate. Turn mathematics into a teaching scene.").foregroundStyle(.secondary)
                }
                Spacer(); Button("Close",systemImage:"xmark") { dismiss() }.labelStyle(.iconOnly).keyboardShortcut(.cancelAction)
            }
            HStack(alignment:.top,spacing:28) {
                VStack(alignment:.leading,spacing:16) {
                    TextField("Scene title",text:$title).font(.title3).textFieldStyle(.roundedBorder)
                    Picker("Shape",selection:$scene.kind) { ForEach(GeometryKind.allCases,id:\.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                    HStack {
                        Text(scene.kind.isRound ? "Radius" : "Side length")
                        TextField("Size",value:$scene.size,format:.number).textFieldStyle(.roundedBorder).frame(width:95)
                        TextField("Unit",text:$scene.unit).textFieldStyle(.roundedBorder).frame(width:80)
                    }
                    if scene.kind.is3D {
                        VStack(alignment:.leading,spacing:10) {
                            HStack { Text("Turn"); Spacer(); Text("\(Int(scene.yaw))°").monospacedDigit() }
                            Slider(value:$scene.yaw,in:-180...180).accessibilityLabel("Turn viewpoint")
                            HStack { Text("Tilt"); Spacer(); Text("\(Int(scene.pitch))°").monospacedDigit() }
                            Slider(value:$scene.pitch,in:-80...80).accessibilityLabel("Tilt viewpoint")
                        }
                    }
                    Divider()
                    Text("SURFACE IMAGE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack {
                        Button("Choose image",systemImage:"photo") { importing = true }
                        PlaygroundButton(isPresented:$playground)
                    }
                    if let texture = scene.texture, let image = store.images[texture] {
                        HStack {
                            Image(nsImage:image).resizable().scaledToFit().frame(width:64,height:64)
                            Text("Image maps onto the shape's surface.").font(.caption).foregroundStyle(.secondary)
                            Button("Remove") { scene.texture = nil }
                        }
                    } else { Text("Squares and cubes use a calculated grid by default.").font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    if targetSlideID != nil { Toggle("Replace selected slide",isOn:$replaceSelected) }
                    Label(connected ? "Local renderer connected" : "Open the KSlides connection in Codex to render",systemImage:connected ? "checkmark.circle.fill" : "link").font(.caption).foregroundStyle(connected ? Color.studioAccent : .secondary)
                    Button("Render into lesson",systemImage:"cube.transparent") { render() }.buttonStyle(.borderedProminent).disabled(!connected || (try? scene.validated()) == nil)
                    if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
                }.frame(width:340)
                VStack(spacing:12) {
                    GeometryWirePreview(scene:scene).frame(height:330).background(Color(nsColor:NSColor(hex:"FFF8E8")),in:RoundedRectangle(cornerRadius:14))
                    Text("Live geometry preview · final surface and lighting are rendered locally").font(.caption).foregroundStyle(.secondary)
                    Text(scene.dimensionLabel).font(.title3.weight(.semibold))
                    Text(scene.formula).font(.callout)
                    Text(scene.secondaryFormula).font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    ForEach(jobs) { job in
                        HStack(spacing:12) {
                            if job.state == "running" { ProgressView().controlSize(.small) }
                            else { Image(systemName:job.state == "applied" ? "checkmark.circle.fill" : "cube").foregroundStyle(Color.studioAccent) }
                            VStack(alignment:.leading,spacing:3) { Text(job.title).font(.callout.weight(.medium)); Text(job.message).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if ["queued","running"].contains(job.state) { Button("Cancel") { store.handle { _ = try store.geometryRPC("kslides_cancel_render",["job_id":job.id.uuidString]) } } }
                            if job.state == "ready" { Button("Add finished scene") { store.handle { _ = try store.applyGeometryJob(job.id,expected:store.lesson(job.lessonID).revision) } } }
                            if job.state == "applied" { Button("View slide") { store.select(job.lessonID); store.selectedSlideID = job.appliedSlideID; dismiss() } }
                        }.padding(10).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))
                    }
                }
            }.frame(height:140)
        }
        .padding(28).frame(width:940,height:790)
        .modifier(PlaygroundSheet(isPresented:$playground,concept:"A colorful educational illustration for a \(scene.kind.label.lowercased()) surface") { url in importTexture(url) })
        .fileImporter(isPresented:$importing,allowedContentTypes:[.png,.jpeg]) { result in
            do { importTexture(try result.get()) } catch { localError = error.localizedDescription }
        }
        .onChange(of:scene.kind) { _,kind in if title.hasPrefix("Explore a ") { title = "Explore a \(kind.rawValue)" } }
        .task {
            if let texture = scene.texture, store.images[texture] == nil { store.images[texture] = NSImage(contentsOf:store.assets.appendingPathComponent(texture)) }
            while !Task.isCancelled { clock = Date(); try? await Task.sleep(for:.seconds(2)) }
        }
    }
    func render() {
        do {
            let lesson = try store.lesson(lessonID)
            _ = try store.enqueueGeometry(lessonID:lessonID,slideID:replaceSelected ? targetSlideID : nil,expected:lesson.revision,scene:scene,title:title)
            localError = nil
        } catch { localError = error.localizedDescription }
    }
    func importTexture(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { scene.texture = try store.importGeometryTexture(Data(contentsOf:url)); localError = nil }
        catch { localError = error.localizedDescription }
    }
}

struct PlaygroundButton: View {
    @Binding var isPresented: Bool
    var body: some View {
        if #available(macOS 15.1, *) { AvailablePlaygroundButton(isPresented:$isPresented) }
        else { Text("Image Playground needs macOS 15.1+").font(.caption).foregroundStyle(.secondary) }
    }
}
@available(macOS 15.1, *) struct AvailablePlaygroundButton: View {
    @Binding var isPresented: Bool
    @Environment(\.supportsImagePlayground) private var supported
    var body: some View { Button("Image Playground",systemImage:"sparkles") { isPresented = true }.disabled(!supported).help(supported ? "Create an illustration for the surface" : "Image Playground is unavailable. Check Apple Intelligence in System Settings.") }
}
struct PlaygroundSheet: ViewModifier {
    @Binding var isPresented: Bool
    let concept: String
    let onCompletion: (URL) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.1, *) { content.imagePlaygroundSheet(isPresented:$isPresented,concepts:[.text(concept)],onCompletion:onCompletion) }
        else { content }
    }
}

struct GeometryWirePreview: View {
    let scene: GeometryScene
    var body: some View {
        Canvas { context,size in
            let center = CGPoint(x:size.width/2,y:size.height/2), scale = min(size.width,size.height)*0.28
            let yaw = scene.yaw * .pi/180, pitch = scene.pitch * .pi/180
            func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
                let right = x*cos(yaw)+y*sin(yaw)
                let forward = -x*sin(yaw)+y*cos(yaw)
                return CGPoint(x:center.x+right*scale,y:center.y-(z*cos(pitch)+forward*sin(pitch))*scale)
            }
            func stroke(_ points: [CGPoint], close: Bool = false) {
                var path = Path(); if let first = points.first { path.move(to:first); for p in points.dropFirst() { path.addLine(to:p) }; if close { path.closeSubpath() } }
                context.stroke(path,with:.color(Color(nsColor:NSColor(hex:"214FDB"))),lineWidth:2)
            }
            switch scene.kind {
            case .circle: stroke((0...120).map { let a = Double($0)*2 * .pi/120; return CGPoint(x:center.x+scale*cos(a),y:center.y+scale*sin(a)) },close:true)
            case .square: stroke([CGPoint(x:center.x-scale,y:center.y-scale),CGPoint(x:center.x+scale,y:center.y-scale),CGPoint(x:center.x+scale,y:center.y+scale),CGPoint(x:center.x-scale,y:center.y+scale)],close:true)
            case .cube:
                let vertices = [(-1.0,-1.0,-1.0),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
                for edge in [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)] { stroke([project(vertices[edge.0].0,vertices[edge.0].1,vertices[edge.0].2),project(vertices[edge.1].0,vertices[edge.1].1,vertices[edge.1].2)]) }
            case .sphere:
                for latitude in stride(from:-60.0,through:60.0,by:30) { let p = latitude * .pi/180; stroke((0...120).map { let a = Double($0)*2 * .pi/120; return project(cos(p)*cos(a),cos(p)*sin(a),sin(p)) }) }
                for longitude in stride(from:0.0,to:180.0,by:30) { let p = longitude * .pi/180; stroke((0...120).map { let a = Double($0)*2 * .pi/120; return project(cos(a)*cos(p),cos(a)*sin(p),sin(a)) }) }
            }
        }.accessibilityLabel("Interactive \(scene.kind.label.lowercased()) geometry preview")
    }
}
