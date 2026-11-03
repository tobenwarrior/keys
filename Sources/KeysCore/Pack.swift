import Foundation

public struct Slice: Equatable {
    public var startMs: Double
    public var endMs: Double?

    public init(startMs: Double, endMs: Double?) {
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct KeyClip: Equatable {
    public var file: URL
    public var down: Slice
    public var up: Slice?
}

public enum PackKind: String, Equatable {
    case keyboard
    case mouse
}

public struct SoundPack: Equatable {
    public var id: String
    public var name: String
    public var kind: PackKind
    public var fallback: String
    public var clips: [String: KeyClip]
}

public struct ResolvedClip: Equatable {
    public var kind: PackKind
    public var file: URL
    public var slice: Slice
    public var rate: Double
}

public struct PackScan: Equatable {
    public var packs: [SoundPack]
    public var errors: [String]
}

public enum PackError: Error, Equatable {
    case invalid(String)
    case unsafePath(String)
}

public func depthRate(for control: String) -> Double {
    switch control {
    case "Space":
        return 0.86
    case "Enter", "NumpadEnter":
        return 0.93
    default:
        return 1
    }
}

public func resolve(pack: SoundPack, control: String, down: Bool) -> ResolvedClip? {
    if control.hasPrefix("Mouse"), pack.kind != .mouse, pack.clips[control] == nil {
        return nil
    }
    let clip: KeyClip?
    if let own = pack.clips[control] {
        clip = own
    } else if pack.kind == .keyboard, !control.hasPrefix("Mouse") {
        clip = pack.clips[pack.fallback]
    } else {
        clip = nil
    }
    guard let clip else { return nil }
    let slice = down ? clip.down : clip.up
    guard let slice else { return nil }
    return ResolvedClip(kind: pack.kind, file: clip.file, slice: slice, rate: depthRate(for: control))
}

public func scanPacks(at root: URL) -> PackScan {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
        return PackScan(packs: [], errors: [])
    }
    var packs: [SoundPack] = []
    var errors: [String] = []
    func take(_ result: Result<SoundPack, Error>, folder: String) {
        switch result {
        case .success(let pack):
            if packs.contains(where: { $0.id == pack.id }) {
                errors.append("Skipped \(folder): duplicate id \(pack.id)")
            } else {
                packs.append(pack)
            }
        case .failure(let error):
            errors.append("Skipped \(folder): \(error)")
        }
    }
    if fm.fileExists(atPath: root.appendingPathComponent("config.json").path) {
        take(Result { try loadPack(at: root) }, folder: root.lastPathComponent)
        return PackScan(packs: packs, errors: errors)
    }
    let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        var childIsDir: ObjCBool = false
        guard fm.fileExists(atPath: child.path, isDirectory: &childIsDir), childIsDir.boolValue else { continue }
        if fm.fileExists(atPath: child.appendingPathComponent("config.json").path) {
            take(Result { try loadPack(at: child) }, folder: child.lastPathComponent)
            continue
        }
        let nested = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for folder in nested.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard fm.fileExists(atPath: folder.appendingPathComponent("config.json").path) else { continue }
            take(Result { try loadPack(at: folder) }, folder: "\(child.lastPathComponent)/\(folder.lastPathComponent)")
        }
    }
    return PackScan(packs: packs, errors: errors)
}

public func loadPack(at directory: URL) throws -> SoundPack {
    let configURL = directory.appendingPathComponent("config.json")
    let data = try Data(contentsOf: configURL)
    let raw = try JSONDecoder().decode(RawPack.self, from: data)
    let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if name.isEmpty { throw PackError.invalid("missing name") }
    let definitions = raw.definitions ?? raw.defs ?? [:]
    if definitions.isEmpty { throw PackError.invalid("missing definitions") }
    let method = (raw.definitionMethod ?? "single").lowercased()
    let sharedName = raw.audioFile
    var clips: [String: KeyClip] = [:]
    for key in definitions.keys.sorted() {
        let spec = definitions[key]!
        let fileName: String?
        if method == "multi" {
            fileName = spec.audioFile ?? sharedName
        } else {
            fileName = spec.audioFile ?? sharedName
        }
        guard let fileName else { throw PackError.invalid("\(key) has no audio file") }
        let file = try safeAudioURL(directory: directory, name: fileName)
        if !FileManager.default.fileExists(atPath: file.path) {
            throw PackError.invalid("missing audio \(fileName)")
        }
        let segments = spec.timing ?? []
        let down: Slice
        let up: Slice?
        if segments.isEmpty {
            down = Slice(startMs: 0, endMs: nil)
            up = nil
        } else {
            guard let first = slice(from: segments[0]) else {
                throw PackError.invalid("\(key) has an empty range")
            }
            down = first
            if segments.count >= 2 {
                up = slice(from: segments[1])
            } else {
                up = nil
            }
        }
        clips[key] = KeyClip(file: file, down: down, up: up)
    }
    let id = portableID(raw.id) ?? directory.lastPathComponent
    let kind = kindOf(raw: raw, names: Array(clips.keys))
    let fallback = clips["KeyA"] != nil ? "KeyA" : (clips.keys.sorted().first ?? "")
    return SoundPack(id: id, name: name, kind: kind, fallback: fallback, clips: clips)
}

private func kindOf(raw: RawPack, names: [String]) -> PackKind {
    if let declared = raw.soundpackType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        if declared == "mouse" { return .mouse }
        if declared == "keyboard" { return .keyboard }
    }
    if !names.isEmpty, names.allSatisfy({ $0.hasPrefix("Mouse") }) { return .mouse }
    return .keyboard
}

private func slice(from pair: [Double]) -> Slice? {
    guard pair.count >= 2 else { return nil }
    let start = pair[0]
    let end = pair[1]
    if start < 0 || end <= start { return nil }
    return Slice(startMs: start, endMs: end)
}

private func portableID(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return nil }
    if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains(":") { return nil }
    return trimmed
}

private func safeAudioURL(directory: URL, name: String) throws -> URL {
    if name.isEmpty || name.hasPrefix("/") || name.contains("..") || name.contains("\\") {
        throw PackError.unsafePath(name)
    }
    return directory.appendingPathComponent(name)
}

private struct RawPack: Decodable {
    var id: String?
    var name: String?
    var audioFile: String?
    var definitionMethod: String?
    var soundpackType: String?
    var definitions: [String: RawDef]?
    var defs: [String: RawDef]?

    enum CodingKeys: String, CodingKey {
        case id, name, definitions, defs
        case audioFile = "audio_file"
        case definitionMethod = "definition_method"
        case soundpackType = "soundpack_type"
    }
}

private struct RawDef: Decodable {
    var audioFile: String?
    var timing: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case timing
        case audioFile = "audio_file"
    }
}
