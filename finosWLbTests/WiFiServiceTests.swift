import Foundation
import Testing
@testable import finosWLb

@Suite("WiFiService.normalizeBssid")
struct WiFiServiceTests {

    @Test("Pads single-hex octets to two digits")
    func padsSingleHex() {
        // Apple NEHotspotNetwork drops leading zeros: "26:b:2a:c7:68:a"
        // should become the canonical form.
        #expect(WiFiService.normalizeBssid("26:b:2a:c7:68:a") == "26:0b:2a:c7:68:0a")
    }

    @Test("Leaves already-canonical input untouched")
    func leavesCanonical() {
        #expect(WiFiService.normalizeBssid("a4:83:e7:12:34:56") == "a4:83:e7:12:34:56")
    }

    @Test("Lowercases uppercase hex")
    func lowercases() {
        #expect(WiFiService.normalizeBssid("A4:83:E7:12:34:56") == "a4:83:e7:12:34:56")
    }

    @Test("Trims surrounding whitespace")
    func trimsWhitespace() {
        #expect(WiFiService.normalizeBssid("  a4:83:e7:12:34:56  ") == "a4:83:e7:12:34:56")
    }

    @Test("Rejects fewer than six octets")
    func tooFewOctets() {
        #expect(WiFiService.normalizeBssid("26:b:2a:c7:68") == nil)
    }

    @Test("Rejects more than six octets")
    func tooManyOctets() {
        #expect(WiFiService.normalizeBssid("26:b:2a:c7:68:0a:ff") == nil)
    }

    @Test("Rejects empty octet (trailing colon)")
    func emptyOctet() {
        #expect(WiFiService.normalizeBssid("26:b:2a:c7:68:") == nil)
    }

    @Test("Rejects non-hex characters")
    func nonHex() {
        #expect(WiFiService.normalizeBssid("26:b:2a:c7:68:zz") == nil)
    }

    @Test("Rejects empty string")
    func emptyString() {
        #expect(WiFiService.normalizeBssid("") == nil)
    }

    @Test("Rejects octet with 3+ characters")
    func overlongOctet() {
        #expect(WiFiService.normalizeBssid("26:bbb:2a:c7:68:0a") == nil)
    }
}
