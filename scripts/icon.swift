import AppKit
import Foundation
let output = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(srgbRed:0.12,green:0.28,blue:0.28,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:s*0.04,y:s*0.04,width:s*0.92,height:s*0.92),xRadius:s*0.20,yRadius:s*0.20).fill()
    NSColor(srgbRed:0.77,green:0.45,blue:0.31,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:s*0.19,y:s*0.21,width:s*0.62,height:s*0.49),xRadius:s*0.04,yRadius:s*0.04).fill()
    NSColor(srgbRed:0.97,green:0.92,blue:0.83,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:s*0.15,y:s*0.28,width:s*0.62,height:s*0.49),xRadius:s*0.04,yRadius:s*0.04).fill()
    let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:s*0.36,weight:.semibold),.foregroundColor:NSColor(srgbRed:0.12,green:0.28,blue:0.28,alpha:1)]
    let letter = NSAttributedString(string:"K",attributes:attrs)
    let extent = letter.size()
    letter.draw(at:NSPoint(x:s*0.46-extent.width/2,y:s*0.53-extent.height/2))
    image.unlockFocus()
    let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
    let png = rep.representation(using:.png,properties:[:])!
    let names: [Int:[String]] = [16:["icon_16x16"],32:["icon_16x16@2x","icon_32x32"],64:["icon_32x32@2x"],128:["icon_128x128"],256:["icon_128x128@2x","icon_256x256"],512:["icon_256x256@2x","icon_512x512"],1024:["icon_512x512@2x"]]
    for name in names[size]! { try png.write(to:output.appendingPathComponent(name+".png")) }
}
