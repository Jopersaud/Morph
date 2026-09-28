import ConversionKit

/// Audio and video conversion, including audio extraction from video.
///
/// Backends: AVFoundation for the formats Apple handles; LGPL FFmpeg with VideoToolbox hardware encoders for the rest (SPEC §6).
///
/// Empty until **M4 (AVFoundation) and M5 (FFmpeg)**. Adding a converter means writing the type,
/// listing it in `converters`, and giving it a fixture test (SPEC §14).
public enum MediaEngine: EngineModule {
    public static let id = "media"

    public static let converters: [any Converter.Type] = []
}
