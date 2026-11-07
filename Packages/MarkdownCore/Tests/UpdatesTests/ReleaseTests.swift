import Foundation
import Testing
@testable import Updates

@Suite("Aktualizace: verze a odpověď GitHubu")
struct ReleaseTests {
    @Test func comparesBuildVersions() throws {
        let older = try #require(ReleaseVersion("20261010.1838"))
        let newer = try #require(ReleaseVersion("v20261010.1922"))
        #expect(older < newer)
        #expect(try #require(ReleaseVersion("20261107.0900")) > newer)
        #expect(ReleaseVersion("v20261010.1922") == ReleaseVersion("20261010.1922"))
        #expect(newer.description == "20261010.1922")
    }

    @Test func rejectsMalformedVersions() {
        #expect(ReleaseVersion("") == nil)
        #expect(ReleaseVersion("v1.x") == nil)
        #expect(ReleaseVersion("latest") == nil)
    }

    @Test func parsesLatestRelease() throws {
        let json = """
        {"tag_name": "v20261010.1922", "html_url": "https://github.com/elvisek2020/app-markdown-viewer/releases/tag/v20261010.1922",
         "assets": [
           {"name": "MDView.dmg", "browser_download_url": "https://example.com/MDView.dmg"},
           {"name": "MDView.zip", "browser_download_url": "https://example.com/MDView.zip"}
         ]}
        """
        let release = try Release.parse(Data(json.utf8))
        #expect(release.version.description == "20261010.1922")
        #expect(release.zipURL.absoluteString == "https://example.com/MDView.zip")
    }

    @Test func failsWithoutZipAsset() {
        let json = #"{"tag_name": "v20261010.1922", "html_url": "https://example.com", "assets": []}"#
        #expect(throws: Release.ParseError.missingAsset) { try Release.parse(Data(json.utf8)) }
        #expect(throws: Release.ParseError.invalidJSON) { try Release.parse(Data("{}".utf8)) }
    }
}
