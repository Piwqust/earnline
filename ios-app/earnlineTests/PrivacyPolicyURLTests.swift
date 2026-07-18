import Foundation
import Testing
@testable import earnline

struct PrivacyPolicyURLTests {
    @Test func acceptsOnlyACompleteHTTPSPolicyURL() {
        #expect(PrivacyPolicyURL.url(from: "https://example.com/privacy") == URL(string: "https://example.com/privacy"))
        #expect(PrivacyPolicyURL.url(from: "  https://example.com/privacy  ") == URL(string: "https://example.com/privacy"))
        #expect(PrivacyPolicyURL.url(from: "http://example.com/privacy") == nil)
        #expect(PrivacyPolicyURL.url(from: "$(EARNLINE_PRIVACY_POLICY_URL)") == nil)
        #expect(PrivacyPolicyURL.url(from: "") == nil)
        #expect(PrivacyPolicyURL.url(from: "https://") == nil)
    }
}
