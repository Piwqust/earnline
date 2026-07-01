import Testing
import Foundation
@testable import earnline

struct ValidationTests {
    @Test func clampsAboveMaximum() {
        #expect(Validation.clampAmount(Limits.maxAmount + 5) == Limits.maxAmount)
    }
    @Test func clampsNegativeToZero() {
        #expect(Validation.clampAmount(-10) == 0)
    }
    @Test func keepsNormalAmount() {
        #expect(Validation.clampAmount(240) == 240)
    }

    @Test func sanitizeStripsLetters() {
        #expect(Validation.sanitizeAmountInput("12a3b") == "123")
    }
    @Test func sanitizeKeepsSingleSeparator() {
        #expect(Validation.sanitizeAmountInput("1.2.3") == "1.23")
        #expect(Validation.sanitizeAmountInput("1,50") == "1.50")
    }
    @Test func sanitizeCapsDigitCount() {
        let input = String(repeating: "9", count: 30)
        #expect(Validation.sanitizeAmountInput(input).count == Limits.maxAmountDigits)
    }

    @Test func cappedTruncates() {
        let s = String(repeating: "a", count: 100)
        #expect(Validation.capped(s, max: Limits.maxProjectLength).count == Limits.maxProjectLength)
    }
    @Test func trimmedTrimsAndCaps() {
        #expect(Validation.trimmed("  hello  ", max: 40) == "hello")
        let long = "  " + String(repeating: "x", count: 200) + "  "
        #expect(Validation.trimmed(long, max: Limits.maxTaskLength).count == Limits.maxTaskLength)
    }

    @Test func clientNameValidationTrimsAndAcceptsUniqueName() {
        #expect(Validation.validateClientName("  Acme Studio  ", existingNames: []) == .valid("Acme Studio"))
    }

    @Test func clientNameValidationRejectsEmptyNames() {
        #expect(Validation.validateClientName("   ", existingNames: []) == .empty)
    }

    @Test func clientNameValidationRejectsCaseInsensitiveDuplicates() {
        #expect(Validation.validateClientName("acme studio", existingNames: ["Acme Studio"]) == .duplicate)
    }

    @Test func clientNameValidationAppliesMaxLength() {
        let long = String(repeating: "a", count: Limits.maxClientNameLength + 10)
        #expect(Validation.validateClientName(long, existingNames: []) == .valid(String(long.prefix(Limits.maxClientNameLength))))
    }
}
