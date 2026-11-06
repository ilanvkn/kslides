import Foundation

public enum StoredZIP {
    public static func archive(_ files: [(String, Data)]) -> Data {
        var output = Data(); var central = Data()
        for (name, bytes) in files {
            let filename = Data(name.utf8)
            let crc = crc32(bytes); let size = UInt32(bytes.count); let offset = UInt32(output.count)
            output.le(UInt32(0x04034b50)); output.le(UInt16(20)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(0x21)); output.le(crc); output.le(size); output.le(size); output.le(UInt16(filename.count)); output.le(UInt16(0)); output.append(filename); output.append(bytes)
            central.le(UInt32(0x02014b50)); central.le(UInt16(20)); central.le(UInt16(20)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0x21)); central.le(crc); central.le(size); central.le(size); central.le(UInt16(filename.count)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt32(0)); central.le(offset); central.append(filename)
        }
        let start = UInt32(output.count); output.append(central)
        output.le(UInt32(0x06054b50)); output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(files.count)); output.le(UInt16(files.count)); output.le(UInt32(central.count)); output.le(start); output.le(UInt16(0))
        return output
    }
    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) } }
        return crc ^ 0xffffffff
    }
}
private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of:&v) { append(contentsOf:$0) }
    }
}
