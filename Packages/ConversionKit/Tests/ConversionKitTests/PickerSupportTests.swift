import Foundation
import Testing

@testable import ConversionKit

@Suite("Picker search and batch reports")
struct PickerSupportTests {

    let images = [
        FormatCatalog.jpeg, FormatCatalog.png, FormatCatalog.heic, FormatCatalog.tiff,
        FormatCatalog.bmp, FormatCatalog.pdf,
    ]

    @Test("A blank query keeps every target in order")
    func blankQuery() {
        #expect(TargetSearch.filter(images, query: "") == images)
        #expect(TargetSearch.filter(images, query: "  ") == images)
    }

    @Test("A prefix finds the format", arguments: [("pn", "png"), ("j", "jpg"), ("TIF", "tiff")])
    func prefix(query: String, expected: String) {
        #expect(TargetSearch.filter(images, query: query).first?.id == expected)
    }

    @Test("Exact matches beat prefixes, and non-matches drop out")
    func ranking() {
        let formats = [FormatCatalog.markdown, FormatCatalog.m4a, FormatCatalog.mp4]
        #expect(TargetSearch.filter(formats, query: "md") == [FormatCatalog.markdown])
        #expect(TargetSearch.filter(formats, query: "m4").map(\.id) == ["m4a"])
        #expect(TargetSearch.filter(images, query: "zzz").isEmpty)
    }

    @Test("Display names match too")
    func displayNames() {
        #expect(TargetSearch.filter([FormatCatalog.txt], query: "plain") == [FormatCatalog.txt])
        #expect(TargetSearch.filter([FormatCatalog.txt], query: "text") == [FormatCatalog.txt])
    }

    private func report(finished: Int, failed: Int = 0, cancelled: Int = 0) -> BatchReport {
        var report = BatchReport()
        for index in 0..<finished {
            report.record(
                .finished(jobID: UUID(), output: URL(fileURLWithPath: "/tmp/photo-\(index).jpg")))
        }
        for _ in 0..<failed {
            report.record(.failed(jobID: UUID(), error: .engine("Broken.")))
        }
        for _ in 0..<cancelled {
            report.record(.cancelled(jobID: UUID()))
        }
        return report
    }

    @Test("Batch reports read as sentences")
    func batchMessages() {
        #expect(report(finished: 1).message == "Converted photo-0.jpg.")
        #expect(report(finished: 12).message == "Converted 12 files.")
        #expect(report(finished: 10, failed: 2).message == "Converted 10 of 12 files. 2 failed.")
        #expect(report(finished: 0, failed: 1).message == "Broken.")
        #expect(report(finished: 0, failed: 3).message == "Couldn't convert 3 files.")
        #expect(report(finished: 0, cancelled: 5).message == nil)
        #expect(report(finished: 2, cancelled: 3).message == "Converted 2 files.")
    }
}
