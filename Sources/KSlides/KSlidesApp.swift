import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import KSlidesCore

extension Color {
    static var studioAccent: Color {
        Color(nsColor:NSColor(name:"KSlidesAction") { appearance in
            NSColor(hex:appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? "9ACABB" : "245B59")
        })
    }
}

@main struct KSlidesApp: App {
    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of:"--verify-designs"), args.count > index+1 {
            do { try DesignVerification.run(root:URL(fileURLWithPath:args[index+1])); Darwin.exit(0) }
            catch { print("FAIL: \(error.localizedDescription)"); Darwin.exit(1) }
        }
    }
    @State private var store = StudioStore()
    var body: some Scene {
        Window("KSlides", id:"studio") {
            StudioView(store:store).task { store.start() }
        }
        .defaultSize(width:1440,height:940)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing:.newItem) { Button("New Lesson") { NotificationCenter.default.post(name:.init("KSlidesNewLesson"),object:nil) }.keyboardShortcut("n") }
            CommandMenu("Lesson") {
                Button("Copy Agent Brief") { store.copyBrief() }.keyboardShortcut("b",modifiers:[.command,.shift])
                Button("Show Exports") { NSWorkspace.shared.open(store.exports) }
            }
            SidebarCommands(); ToolbarCommands()
        }
        Window("Classroom", id:"classroom") { ClassroomView(store:store) }.defaultSize(width:1280,height:760)
        Settings { SettingsView(store:store) }
    }
}

struct StudioView: View {
    @Bindable var store: StudioStore
    @Environment(\.openWindow) private var openWindow
    @State private var overview = false
    @State private var choosingDesign = false
    @State private var creating = false
    @State private var connecting = false
    @State private var importing = false
    @State private var importingArt = false
    @State private var inspectorTab = 0
    @State private var compact = false
    @State private var compactInspector = false
    @State private var geometryLab = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    Image(systemName:"rectangle.on.rectangle.angled").font(.system(size:26)).foregroundStyle(Color.studioAccent)
                    VStack(alignment:.leading,spacing:2) { Text("KSlides").font(.system(size:25,weight:.semibold,design:.serif)); Text("Make learning come alive").foregroundStyle(.secondary).font(.caption) }
                }.padding(20)
                Button { creating = true } label: { Label("New lesson",systemImage:"plus").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).padding(.horizontal,16).padding(.bottom,20)
                Text("YOUR LESSONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal,20).padding(.bottom,8)
                List(selection:$store.selectedLessonID) {
                    ForEach(store.lessons) { lesson in
                        VStack(alignment:.leading,spacing:6) {
                            Text(lesson.title).font(.headline).lineLimit(2)
                            Text(lesson.audience).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text("\(lesson.slides.count) slides · \(lesson.world.rawValue)").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical,7).tag(lesson.id)
                    }
                }.listStyle(.sidebar)
                VStack(alignment:.leading,spacing:9) {
                    Label(store.serverStatus,systemImage:"point.3.connected.trianglepath.dotted").font(.caption).foregroundStyle(.secondary)
                    Button("Connect an AI agent") { connecting = true }
                    Text("Built by IK").font(.caption2).foregroundStyle(.tertiary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min:220,ideal:260,max:310)
        } detail: {
            if let lesson = store.active {
                GeometryReader { geo in
                    VStack(spacing:0) {
                        HStack(alignment:.top) {
                            VStack(alignment:.leading,spacing:6) { Text(lesson.title).font(.system(size:28,weight:.semibold,design:.serif)); Text("\(lesson.audience) · \(lesson.slides.count) slides · \(lesson.slides.reduce(0) { $0 + $1.durationSeconds } / 60) min").foregroundStyle(.secondary) }
                            Spacer()
                            Menu { ForEach(World.allCases,id:\.self) { world in Button(world.rawValue) { store.handle { var updated = lesson; updated.world = world; try store.replace(updated,expected:lesson.revision) } } } } label: { Label(lesson.world.rawValue,systemImage:"paintpalette") }
                        }.padding(.horizontal,24).padding(.top,22).padding(.bottom,16)
                        HStack {
                            Picker("Workspace",selection:$overview) { Label("Slide editor",systemImage:"rectangle").tag(false); Label("Lesson overview",systemImage:"square.grid.2x2").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width:290)
                            Spacer()
                            Button { choosingDesign = true } label: { Label("Design gallery",systemImage:"paintpalette.fill") }.disabled(store.activeSlide == nil)
                        }.padding(.horizontal,24).padding(.bottom,16)
                        Divider()
                        HStack(spacing:0) {
                            if overview { DeckOverview(store:store,lesson:lesson) { overview = false } } else {
                            VStack(spacing:16) {
                                if let savedSlide = store.activeSlide {
                                    let slide = store.editorDrafts[savedSlide.id] ?? savedSlide
                                    HStack { Text(slide.phase.uppercased()).font(.caption.weight(.medium)).foregroundStyle(.secondary); Spacer(); Text("Slide \((lesson.slides.firstIndex(where: { $0.id == slide.id }) ?? 0)+1) of \(lesson.slides.count)").font(.caption).foregroundStyle(.secondary) }
                                    SlideSurface(slide:slide,lesson:lesson,image:slide.artwork.flatMap { store.images[$0] }).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:8)).shadow(color:.black.opacity(0.12),radius:20,y:8)
                                    HStack {
                                        Label(slide.studentAction.isEmpty ? "Add a student action in the inspector" : slide.studentAction,systemImage:"hand.raised").foregroundStyle(.secondary).font(.callout)
                                        Spacer()
                                        if slide.artwork == nil { Text("Artwork pending").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength:0)
                                } else { ContentUnavailableView("Your lesson starts here",systemImage:"rectangle.stack",description:Text("Add a slide or copy the brief for your AI agent.")); Spacer() }
                            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
                            }
                            if !overview && store.inspectorVisible && geo.size.width > 850 {
                                Divider()
                                inspector(lesson).frame(width:300)
                            }
                        }
                        Divider()
                        filmstrip(lesson)
                        HStack {
                            Text(store.activeHasDraft ? "Unsaved slide edits · save or reload in the inspector before exporting or teaching." : (store.message.isEmpty ? "Changes save locally. Your lesson stays yours." : store.message)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Spacer(); Text("Revision \(lesson.revision)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(.horizontal,24).padding(.vertical,10)
                    }
                    .onChange(of:geo.size.width, initial:true) { _,width in compact = width <= 850 }
                }
            } else { ContentUnavailableView("Create a lesson",systemImage:"rectangle.stack.badge.plus",description:Text("Start with your topic and audience, or import a storyboard.")) }
        }
        .tint(Color.studioAccent)
        .frame(minWidth:980,minHeight:680)
        .toolbar {
            ToolbarItemGroup(placement:.primaryAction) {
                Button { geometryLab = true } label: { Label("Geometry Lab",systemImage:"cube.transparent") }.disabled(store.active == nil)
                Button { importing = true } label: { Label("Import",systemImage:"square.and.arrow.down") }.help("Import a KSlides lesson or Lesson World JSON plan")
                Button { store.copyBrief() } label: { Label("Agent brief",systemImage:"sparkles") }.help("Copy your lesson brief for Codex or another AI agent")
                Button { importingArt = true } label: { Label("Artwork",systemImage:"photo.badge.plus") }.disabled(store.activeSlide == nil)
                Button { if compact { compactInspector = true } else { store.inspectorVisible.toggle() } } label: { Label("Inspector",systemImage:"sidebar.right") }
                Menu {
                    Button("PowerPoint (.pptx)") { export("pptx") }
                    Button("Slides as PDF") { export("pdf") }
                    Button("Slide images (.png)") { export("png") }
                    Button("Printable worksheet") { export("worksheet") }
                    Button("Lesson source (.json)") { export("json") }
                    Divider(); Button("Show exports") { NSWorkspace.shared.open(store.exports) }
                } label: { Label("Export",systemImage:"square.and.arrow.up") }.disabled(store.active?.slides.isEmpty ?? true)
                Button { openWindow(id:"classroom") } label: { Label("Teach",systemImage:"play.fill") }.disabled(!store.canTeach)
            }
        }
        .onChange(of:store.selectedLessonID) { _,_ in store.selectedSlideID = store.active?.slides.first?.id }
        .onReceive(NotificationCenter.default.publisher(for:.init("KSlidesNewLesson"))) { _ in creating = true }
        .sheet(isPresented:$choosingDesign) { if let lesson = store.active, let slide = store.activeSlide { DesignGallery(store:store,lesson:lesson,slide:slide) } }
        .sheet(isPresented:$creating) { NewLessonView(store:store) }
        .sheet(isPresented:$geometryLab) { if let lesson = store.active { GeometryLab(store:store,lesson:lesson) } }
        .sheet(isPresented:$connecting) { AgentConnectionView(store:store) }
        .sheet(isPresented:$compactInspector) { if let lesson = store.active { inspector(lesson).frame(width:420,height:650) } }
        .alert("KSlides needs your attention",isPresented:Binding(get:{store.error != nil},set:{ if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
            store.handle {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf:url)
                if let lesson = try? JSONDecoder().decode(Lesson.self,from:data) {
                    _ = try store.create(lesson.copyWithoutArtwork())
                } else { guard let plan = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw StudioError.invalid("Invalid lesson JSON.") }; _ = try store.importPlan(plan) }
            }
        }
        .fileImporter(isPresented:$importingArt,allowedContentTypes:[.png,.jpeg]) { result in
            store.handle {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let lesson = store.active, let slide = store.activeSlide else { throw StudioError.invalid("Select a slide first.") }
                _ = try store.attach(Data(contentsOf:url),to:lesson.id,slideID:slide.id,expected:lesson.revision,provenance:"User-selected image: \(url.lastPathComponent)")
            }
        }
    }
    @ViewBuilder func inspector(_ lesson: Lesson) -> some View {
        if let slide = store.activeSlide { SlideInspector(store:store,lesson:lesson,slide:slide).id(slide.id) }
        else { ContentUnavailableView("Select a slide",systemImage:"sidebar.right") }
    }
    func export(_ format: String) {
        store.handle { guard let lesson = store.active else { return }; guard !store.activeHasDraft else { throw StudioError.invalid("Save or reload your slide edits before exporting.") }; let files = try Exporter.export(lesson,format:format,store:store); store.message = "Exported \(format.uppercased()) · \(files.count) file\(files.count == 1 ? "" : "s")"; NSWorkspace.shared.activateFileViewerSelecting(files) }
    }
    func filmstrip(_ lesson: Lesson) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing:14) {
                ForEach(Array(lesson.slides.enumerated()),id:\.element.id) { index,saved in
                    let slide = store.editorDrafts[saved.id] ?? saved
                    Button { store.selectedSlideID = slide.id } label: {
                        VStack(alignment:.leading,spacing:6) {
                            SlideSurface(slide:slide,lesson:lesson,image:slide.artwork.flatMap { store.images[$0] }).frame(width:150,height:84).clipShape(RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(store.selectedSlideID == slide.id ? Color.accentColor : .clear,lineWidth:3))
                            Text("\(index+1). \(slide.title)").font(.caption).lineLimit(1).frame(width:150,alignment:.leading)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Slide \(index+1): \(slide.title)")
                }
                Button {
                    store.handle { var updated = lesson; let slide = Slide(title:"New teaching scene"); updated.slides.append(slide); try store.replace(updated,expected:lesson.revision); store.selectedSlideID = slide.id }
                } label: { VStack(spacing:10) { Image(systemName:"plus").font(.title2); Text("Add slide").font(.caption) }.frame(width:110,height:84) }.buttonStyle(.bordered)
            }.padding(20)
        }.frame(height:150)
    }
}

struct SlideSurface: NSViewRepresentable {
    let slide: Slide
    let lesson: Lesson
    let image: NSImage?
    func makeNSView(context: Context) -> RenderView { RenderView() }
    func updateNSView(_ view: RenderView, context: Context) {
        view.slide = slide; view.lesson = lesson; view.image = image; view.needsDisplay = true
        view.setAccessibilityElement(true); view.setAccessibilityRole(.image)
        view.setAccessibilityLabel(slide.title + ". " + slide.body)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RenderView, context: Context) -> CGSize? {
        if let w = proposal.width, let h = proposal.height { return CGSize(width:min(w,h*16/9),height:min(h,w*9/16)) }
        if let w = proposal.width { return CGSize(width:w,height:w*9/16) }
        if let h = proposal.height { return CGSize(width:h*16/9,height:h) }
        return CGSize(width:1280,height:720)
    }
    @MainActor final class RenderView: NSView {
        var slide: Slide?
        var lesson: Lesson?
        var image: NSImage?
        override var intrinsicContentSize: NSSize { NSSize(width:NSView.noIntrinsicMetric,height:NSView.noIntrinsicMetric) }
        override func draw(_ dirtyRect: NSRect) {
            guard let slide, let lesson, let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState(); context.scaleBy(x:bounds.width/1280,y:bounds.height/720)
            SlideDrawing.draw(slide,lesson:lesson,image:image,context:context)
            context.restoreGState()
        }
    }
}

struct SlideInspector: View {
    @Bindable var store: StudioStore
    let lesson: Lesson
    let slide: Slide
    @State private var draft: Slide
    @State private var revision: Int
    @State private var tab = 0
    @State private var dirty = false
    init(store: StudioStore, lesson: Lesson, slide: Slide) {
        self.store = store; self.lesson = lesson; self.slide = slide
        _draft = State(initialValue:store.editorDrafts[slide.id] ?? slide)
        _revision = State(initialValue:store.editorRevisions[slide.id] ?? lesson.revision)
        _dirty = State(initialValue:store.editorDrafts[slide.id] != nil)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Slide studio").font(.headline); Spacer(); if dirty { Text("Unsaved").font(.caption).foregroundStyle(.secondary) } }
            Picker("Inspector section",selection:$tab) { Text("Content").tag(0); Text("Artwork").tag(1); Text("Teacher").tag(2) }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if tab == 0 {
                        field(draft.layout == "illustrated" ? "Source title" : "Title",text:$draft.title,height:54)
                        field(draft.layout == "illustrated" ? "Source lettering" : "On-slide text",text:$draft.body,height:160)
                        field("Student action",text:$draft.studentAction,height:68)
                        TextField("Teaching phase",text:$draft.phase)
                        Picker("Composition",selection:$draft.layout) { ForEach(SlideLayout.allCases,id:\.rawValue) { Text($0.label).tag($0.rawValue) } }
                        Picker("Typography",selection:Binding(get:{draft.typography ?? "theme"},set:{draft.typography = $0 == "theme" ? nil : $0})) { Text("Match visual world").tag("theme"); ForEach(TypeStyle.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.disabled(draft.layout == "illustrated")
                        Text(draft.layout == "illustrated" ? "Lettering is part of the artwork. After changing source words, regenerate and attach the slide. Theme and typography controls do not restyle the image." : "Preview updates as you edit. Save to commit your changes.").font(.caption).foregroundStyle(.secondary)
                        Text(draft.layout == "illustrated" ? "Teacher notes and student actions remain separately editable." : "For comparison, concept and sequence cards, separate each idea with a blank line.").font(.caption).foregroundStyle(.secondary)
                        Stepper("\(draft.durationSeconds) seconds",value:$draft.durationSeconds,in:1...3600,step:15)
                    } else if tab == 1 {
                        Text("Generate with your agent").font(.headline)
                        Text(draft.layout == "illustrated" ? "Generate the complete composition and exact lettering together. Copy this prompt to your agent, inspect the result, then attach it." : "Describe this scene, copy its prompt to an image tool, then attach the result. Exact slide text stays editable.").font(.callout).foregroundStyle(.secondary)
                        field("Scene & consistency",text:$draft.imagePrompt,height:260)
                        Button("Copy image prompt") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lesson.prompt(for:draft),forType:.string); store.message = "Image prompt copied" }
                        Text(slide.artwork == nil ? "No artwork attached yet" : "Artwork attached to this slide").font(.caption).foregroundStyle(.secondary)
                    } else {
                        field("Teaching purpose",text:$draft.purpose,height:75)
                        field("Private teacher notes",text:$draft.teacherNotes,height:290)
                        Text("These notes appear in PowerPoint speaker notes. They stay off student slides and worksheet pages.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Reload") { draft = slide; revision = lesson.revision; dirty = false; store.editorDrafts.removeValue(forKey:slide.id); store.editorRevisions.removeValue(forKey:slide.id) }
                Spacer()
                Button("Save changes") {
                    store.handle { var updated = try store.lesson(lesson.id); guard let index = updated.slides.firstIndex(where: { $0.id == draft.id }) else { throw StudioError.invalid("Slide no longer exists.") }; updated.slides[index] = draft; let saved = try store.replace(updated,expected:revision); revision = saved.revision; dirty = false; store.editorDrafts.removeValue(forKey:slide.id); store.editorRevisions.removeValue(forKey:slide.id) }
                }.buttonStyle(.borderedProminent).disabled(!dirty)
            }
            if revision != lesson.revision && dirty { Text("This lesson changed elsewhere. Copy your draft if needed, then reload before saving.").font(.caption).foregroundStyle(.orange) }
            if let issue = SlideDrawing.fitIssue(draft,lesson:lesson) { Text(issue).font(.caption).foregroundStyle(.orange) }
        }.padding(20)
        .onChange(of:draft) { _,_ in dirty = draft != slide; if dirty { store.editorDrafts[slide.id] = draft; store.editorRevisions[slide.id] = revision } }
        .onChange(of:lesson.revision) { _,new in if !dirty { draft = slide; revision = new } }
    }
    func field(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:6) { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary); TextEditor(text:text).font(.system(size:13)).frame(minHeight:height).scrollContentBackground(.hidden).padding(8).background(.background,in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(.quaternary)).accessibilityLabel(label) }
    }
}

struct NewLessonView: View {
    @Bindable var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var topic = ""
    @State private var audience = "Year 2 · ages 7–8"
    @State private var goals = ""
    @State private var content = ""
    @State private var world = World.explorer
    @State private var localError: String?
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("A new learning adventure").font(.system(size:30,weight:.semibold,design:.serif))
            Text("Start with the teaching brief. You or your agent can shape the slides next.").foregroundStyle(.secondary)
            Form {
                TextField("Lesson title",text:$title)
                TextField("Topic",text:$topic)
                TextField("Audience",text:$audience)
                TextField("Learning goals",text:$goals,axis:.vertical).lineLimit(2...4)
                Picker("Visual world",selection:$world) { ForEach(World.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                LabeledContent("Source content") { TextEditor(text:$content).frame(height:150).font(.body) }
            }.formStyle(.grouped)
            if let localError { Text(localError).foregroundStyle(.red).font(.callout) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Create lesson") { do { let value = Lesson(title:title,topic:topic,audience:audience,goals:goals,sourceContent:content,world:world); _ = try store.create(value); dismiss() } catch { localError = error.localizedDescription } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || topic.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width:600,height:620)
    }
}

struct AgentConnectionView: View {
    @Bindable var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    var command: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/KSlidesMCP").path }
    var config: String { "[mcp_servers.kslides]\ncommand = \"\(command)\"\n" }
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            Image(systemName:"point.3.connected.trianglepath.dotted").font(.system(size:36)).foregroundStyle(Color.accentColor)
            Text("Your studio. Your AI agent.").font(.system(size:29,weight:.semibold,design:.serif))
            Text("KSlides exposes real lesson tools through MCP. Your agent plans and generates; you see and refine the result here.").foregroundStyle(.secondary)
            Label(store.serverStatus,systemImage:"checkmark.circle")
            Text("Codex MCP configuration").font(.headline)
            Text(config).font(.system(size:12,design:.monospaced)).textSelection(.enabled).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
            HStack { Button("Copy configuration") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(config,forType:.string) }; Button("Copy lesson brief") { store.copyBrief() }.disabled(store.active == nil) }
            Text("Keep KSlides open while your agent works. Tools can create lessons, edit slides, attach artwork, and export PowerPoint, PDF and images. The bridge reads a local connection file; no API key is stored in a prompt.").font(.callout).foregroundStyle(.secondary)
            Spacer(); HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width:570,height:580)
    }
}

struct SettingsView: View {
    @Bindable var store: StudioStore
    var body: some View {
        Form {
            Section("KSlides") { LabeledContent("Version",value:"0.2.0 · Native Mac preview"); LabeledContent("Agent connection",value:store.serverStatus) }
            Section("Local studio") { Text(store.root.path).font(.caption).textSelection(.enabled); Button("Open studio folder") { NSWorkspace.shared.open(store.root) }; Button("Open exports") { NSWorkspace.shared.open(store.exports) } }
            Section("AI artwork") { Text("Connect Codex or another MCP client. The agent uses its image-generation tool and attaches finished PNG/JPEG artwork to KSlides. No standalone AI subscription is included.").font(.callout) }
        }.formStyle(.grouped).frame(width:530,height:340)
    }
}

struct ClassroomView: View {
    @Bindable var store: StudioStore
    @State private var lesson: Lesson?
    @State private var index = 0
    var body: some View {
        VStack(spacing:0) {
            if let lesson, !lesson.slides.isEmpty {
                SlideSurface(slide:lesson.slides[min(index,lesson.slides.count-1)],lesson:lesson,image:lesson.slides[min(index,lesson.slides.count-1)].artwork.flatMap { store.images[$0] }).aspectRatio(16/9,contentMode:.fit).frame(maxWidth:.infinity,maxHeight:.infinity)
                HStack { Button("Previous",systemImage:"chevron.left") { index = max(0,index-1) }.keyboardShortcut(.leftArrow,modifiers:[]).disabled(index == 0); Spacer(); Text("\(index+1) / \(lesson.slides.count)").monospacedDigit(); Spacer(); Button("Next",systemImage:"chevron.right") { index = min(lesson.slides.count-1,index+1) }.keyboardShortcut(.rightArrow,modifiers:[]).disabled(index == lesson.slides.count-1) }.padding(14)
            } else { ContentUnavailableView("Open a lesson to teach",systemImage:"play.rectangle") }
        }.background(.black).task { loadSelectedLesson() }
        .toolbar { Button("Load selected lesson") { loadSelectedLesson() }.disabled(!store.canTeach) }
    }
    private func loadSelectedLesson() { lesson = store.canTeach ? store.active : nil; index = 0 }
}
