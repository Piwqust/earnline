import Foundation
import Testing
@testable import earnline

struct AuthCallbackTests {
    @Test func acceptsOnlyTheRegisteredOAuthCallbackRoute() {
        let expected = AppModel.oauthRedirectURL
        #expect(AppModel.isExpectedOAuthCallback(expected))

        let wrongHost = URL(string: "\(expected.scheme ?? "com.earnline.app")://other/callback")!
        let wrongPath = URL(string: "\(expected.scheme ?? "com.earnline.app")://auth/other")!
        let wrongScheme = URL(string: "https://auth/callback")!

        #expect(!AppModel.isExpectedOAuthCallback(wrongHost))
        #expect(!AppModel.isExpectedOAuthCallback(wrongPath))
        #expect(!AppModel.isExpectedOAuthCallback(wrongScheme))
    }
}
