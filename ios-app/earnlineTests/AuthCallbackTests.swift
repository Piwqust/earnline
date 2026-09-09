import Foundation
import Testing
@testable import earnline

struct AuthCallbackTests {
    @Test func callbackUsesRegisteredSchemeAfterResigning() {
        let callback = AppModel.registeredOAuthRedirectURL(urlTypes: [["CFBundleURLSchemes": ["com.earnline.app"]]])
        #expect(callback.absoluteString == "com.earnline.app://auth/callback")
        let dev = AppModel.registeredOAuthRedirectURL(urlTypes: [["CFBundleURLSchemes": ["com.earnline.app.dev"]]])
        #expect(dev.absoluteString == "com.earnline.app.dev://auth/callback")
    }

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
