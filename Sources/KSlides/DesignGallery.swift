import AppKit
import SwiftUI
import KSlidesCore

struct DeckOverview: View {
    @Bindable var store: StudioStore
    let lesson: Lesson
    var open: () -> Void
    var body: some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:240,maximum:380),spacing:20)],spacing:24) {
                ForEach(Array(lesson.slides.enumerated()),id:\.element.id) { index,saved in
                    let slide = store.editorDrafts[saved.id] ?? saved
                    Button {
                        store.selectedSlideID = slide.id; open()
                    } label: {
                        VStack(alignment:.leading,spacing:10) {
                            SlideSurface(slide:slide,lesson:lesson,image:slide.artwork.flatMap { store.images[$0] }).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:8))
                            HStack { Text(String(format:"%02d",index+1)).monospacedDigit().foregroundStyle(.secondary); Text(slide.title).font(.headline).lineLimit(1); Spacer() }
                            HStack { Text(SlideLayout(rawValue:slide.layout)?.label ?? slide.layout); Spacer(); Text("\(slide.durationSeconds / 60)m").monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                            if let issue = SlideDrawing.fitIssue(slide,lesson:lesson) { Label(issue,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2) }
                        }.padding(12).background(.background,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(store.selectedSlideID == slide.id ? Color.studioAccent : Color.secondary.opacity(0.15),lineWidth:store.selectedSlideID == slide.id ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("Edit slide \(index+1), \(slide.title), \(SlideLayout(rawValue:slide.layout)?.label ?? slide.layout)")
                }
            }.padding(24)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
    }
}

struct DesignGallery: View {
    @Bindable var store: StudioStore
    let lesson: Lesson
    let slide: Slide
    @Environment(\.dismiss) private var dismiss
    @State private var world: World
    @State private var layout: String
    @State private var typography: String
    @State private var localError: String?
    init(store: StudioStore, lesson: Lesson, slide: Slide) {
        self.store = store; self.lesson = lesson; self.slide = slide
        _world = State(initialValue:lesson.world); _layout = State(initialValue:slide.layout); _typography = State(initialValue:slide.typography ?? "theme")
    }
    var previewLesson: Lesson { var copy = lesson; copy.world = world; return copy }
    func preview(_ layout: SlideLayout) -> Slide {
        var copy = store.editorDrafts[slide.id] ?? slide; copy.layout = layout.rawValue; copy.typography = typography == "theme" ? nil : typography; return copy
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:6) { Text("A design for every teaching moment").font(.system(size:26,weight:.semibold,design:.serif)); Text("Preview native compositions or display a complete illustrated slide.").foregroundStyle(.secondary) }
                Spacer(); Button("Close",systemImage:"xmark") { dismiss() }.labelStyle(.iconOnly).buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            HStack(alignment:.top,spacing:24) {
                ScrollView { VStack(alignment:.leading,spacing:10) {
                    Text("VISUAL WORLD").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(World.allCases,id:\.self) { candidate in
                        Button { world = candidate } label: {
                            HStack(spacing:10) { RoundedRectangle(cornerRadius:4).fill(Color(nsColor:NSColor(hex:candidate.background))).frame(width:24,height:30).overlay(Text("Aa").font(.custom(TypeStyle.themeDefault(candidate).heading,size:10)).foregroundStyle(Color(nsColor:NSColor(hex:candidate.ink)))); Text(candidate.rawValue).font(.callout); Spacer(); if world == candidate { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.studioAccent) } }.padding(8).background(world == candidate ? Color.studioAccent.opacity(0.10) : Color.clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                    Divider()
                    Text("TYPE STYLE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Typography",selection:$typography) { Text("Match visual world").tag("theme"); ForEach(TypeStyle.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden()
                    let type = TypeStyle(rawValue:typography) ?? TypeStyle.themeDefault(world)
                    Text("Aa • Learning").font(.custom(type.heading,size:22))
                    Text("Visual world applies to the lesson. Composition and type apply to this slide.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth:.infinity,alignment:.leading) }.frame(width:210)
                ScrollView {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:230),spacing:16)],spacing:18) {
                        ForEach(SlideLayout.allCases,id:\.rawValue) { candidate in
                            Button { layout = candidate.rawValue } label: {
                                VStack(alignment:.leading,spacing:8) {
                                    SlideSurface(slide:preview(candidate),lesson:previewLesson,image:slide.artwork.flatMap { store.images[$0] }).aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:6))
                                    HStack { Text(candidate.label).font(.callout.weight(.medium)); Spacer(); if layout == candidate.rawValue { Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.studioAccent) } }
                                }.padding(10).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(layout == candidate.rawValue ? Color.studioAccent : Color.secondary.opacity(0.2),lineWidth:layout == candidate.rawValue ? 2 : 1))
                            }.buttonStyle(.plain).accessibilityLabel("Choose \(candidate.label)")
                        }
                    }.padding(3)
                }
            }
            if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
            HStack {
                Text("Illustrated lettering belongs to the image. Native layouts keep text editable.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply design") {
                    do {
                        var updated = try store.lesson(lesson.id)
                        guard store.editorDrafts[slide.id] == nil else { throw StudioError.invalid("Save or reload your text draft before applying a design.") }
                        guard let index = updated.slides.firstIndex(where: { $0.id == slide.id }) else { throw StudioError.invalid("Slide no longer exists.") }
                        updated.world = world; updated.slides[index].layout = layout; updated.slides[index].typography = typography == "theme" ? nil : typography
                        try store.replace(updated,expected:lesson.revision); dismiss()
                    } catch { localError = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:840,height:650)
    }
}
