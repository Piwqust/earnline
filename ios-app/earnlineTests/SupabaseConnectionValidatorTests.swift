import Foundation
import Testing
@testable import earnline

struct SupabaseConnectionValidatorTests {
    @Test func acceptsAHTTPSProjectURLAndPublishableKey() {
        let result = SupabaseConnectionValidator.validate(
            projectURL: " https://example.supabase.co ",
            publishableKey: " sb_publishable_example "
        )

        #expect(result == .valid(URL(string: "https://example.supabase.co")!, "sb_publishable_example"))
    }

    @Test func rejectsUnsafeOrIncompleteConnectionDetails() {
        #expect(SupabaseConnectionValidator.validate(
            projectURL: "http://example.supabase.co",
            publishableKey: "sb_publishable_example"
        ) == .invalid("Enter a valid HTTPS Project URL."))

        #expect(SupabaseConnectionValidator.validate(
            projectURL: "https://example.supabase.co",
            publishableKey: "   "
        ) == .invalid("Enter a publishable key."))

        #expect(SupabaseConnectionValidator.validate(
            projectURL: "https://example.supabase.co",
            publishableKey: "sb_secret_example"
        ) == .invalid("Use a publishable or anon key, never a secret or service-role key."))

        #expect(SupabaseConnectionValidator.validate(
            projectURL: "https://example.supabase.co",
            publishableKey: "header.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"
        ) == .invalid("Use a publishable or anon key, never a secret or service-role key."))
    }
}
