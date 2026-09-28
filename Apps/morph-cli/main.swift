import ConversionKit
import Foundation

/// `morph`, the command-line entry point (SPEC §3, E7).
///
/// M0 ships `--version`, `--help` and `formats`, which is enough to prove the
/// CLI links the same core as the app. `convert` lands in M6, when the CLI gets
/// swift-argument-parser and real option parsing (SPEC §8).
enum MorphCLI {

    static let version = "0.1.0 (M0 scaffold)"

    enum ExitCode: Int32 {
        case success = 0
        case usage = 64
        case unimplemented = 70
    }

    static func run(_ arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return ExitCode.usage.rawValue
        }

        switch command {
        case "--version", "-v", "version":
            print("morph \(version)")
            return ExitCode.success.rawValue

        case "--help", "-h", "help":
            printUsage()
            return ExitCode.success.rawValue

        case "formats":
            printFormats()
            return ExitCode.success.rawValue

        case "convert":
            printError("`morph convert` arrives in M6. Use the app for now.")
            return ExitCode.unimplemented.rawValue

        default:
            printError("Unknown command: \(command)")
            printUsage()
            return ExitCode.usage.rawValue
        }
    }

    private static func printUsage() {
        print(
            """
            morph \(version)
            Local file conversion. Nothing leaves your Mac.

            USAGE
              morph formats            List the formats Morph knows about
              morph convert            Convert files (arrives in M6)
              morph --version          Print the version
              morph --help             Show this message
            """)
    }

    private static func printFormats() {
        for category in FileFormat.Category.allCases {
            let formats = FormatCatalog.formats(in: category)
            guard !formats.isEmpty else { continue }
            print("\(category.displayName):")
            for format in formats {
                print(
                    "  \(format.id.padding(toLength: 8, withPad: " ", startingAt: 0))"
                        + "\(format.displayName) (.\(format.preferredExtension))")
            }
        }
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("morph: \(message)\n".utf8))
    }
}

exit(MorphCLI.run(Array(CommandLine.arguments.dropFirst())))
