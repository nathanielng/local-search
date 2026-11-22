import Foundation

/// ls-style colour categories. Extensions win over the executable bit
/// (a .jpg with mode 755 is still an image).
public enum FileColor: String, Sendable, CaseIterable {
    case directory, symlink, archive, image, audio, video, executable, plain

    static let archives: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "iso", "zst"]
    static let images: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "webp", "svg", "ico", "psd", "raw"]
    static let audios: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "ogg", "aiff", "opus"]
    static let videos: Set<String> = ["mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv", "flv"]

    public static func classify(name: String, isDirectory: Bool, isSymlink: Bool, isExecutable: Bool) -> FileColor {
        if isSymlink { return .symlink }
        if isDirectory { return .directory }
        let ext = (name as NSString).pathExtension.lowercased()
        if archives.contains(ext) { return .archive }
        if images.contains(ext) { return .image }
        if audios.contains(ext) { return .audio }
        if videos.contains(ext) { return .video }
        return isExecutable ? .executable : .plain
    }
}
