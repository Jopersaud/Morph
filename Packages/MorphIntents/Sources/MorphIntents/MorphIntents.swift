import ConversionKit

/// App Intents, which make Morph scriptable from Shortcuts and Automator
/// (SPEC §3, E6).
///
/// Empty until **M6**. The `Convert Files` intent lands here, taking files, a
/// target format and options. Intents run in the app's process, so they reach
/// the same `ConversionService` as every other entry point.
public enum MorphIntents {
    /// Formats offered as the intent's target parameter. Shortcuts shows these
    /// as a picker, so the list matches the catalog rather than the routes that
    /// happen to be registered.
    public static var offeredTargets: [FileFormat] { FormatCatalog.all }
}
