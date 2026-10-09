import Foundation
import Testing
@testable import ExpenseCore

@Suite struct GouacheToneTests {
    /// Значения совпадают с `.impeccable/design.json` → `extensions.colorMeta.<tone>.canonical`.
    @Test func mainHexMatchesDesignJSON() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".impeccable/design.json")
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let extensions = try #require(root["extensions"] as? [String: Any])
        let meta = try #require(extensions["colorMeta"] as? [String: Any])
        for tone in GouacheTone.allCases {
            let entry = try #require(meta[tone.rawValue] as? [String: Any], "нет тона \(tone.rawValue)")
            #expect((entry["canonical"] as? String)?.uppercased() == tone.mainHex)
        }
    }

    @Test func lookupByHexIgnoresCase() {
        #expect(GouacheTone(mainHex: "#3e9b6b") == .shalfey)
        #expect(GouacheTone(mainHex: "#000000") == nil)
        #expect(GouacheTone.krapplak.hueRank == 0)
        #expect(GouacheTone.grafit.hueRank == 14)
    }
}
