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

    @Test func snapsAmountsToTwoDecimalPlaces() {
        #expect(Validation.clampAmount(Decimal(string: "10.999", locale: Locale(identifier: "en_US_POSIX"))!)
                == Decimal(string: "11.00", locale: Locale(identifier: "en_US_POSIX"))!)
        #expect(Validation.clampAmount(Decimal(string: "10.994", locale: Locale(identifier: "en_US_POSIX"))!)
                == Decimal(string: "10.99", locale: Locale(identifier: "en_US_POSIX"))!)
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

    @Test(arguments: ["0.001", "12.345", "1,234", "1.2.3", "2000000000", "0", "-1", "12a3", "1 23.45"])
    func moneyFieldRejectsAmbiguousOrInvalidAmounts(input: String) {
        #expect(Validation.moneyAmount(from: input) == nil)
    }

    @Test(arguments: ["1,234.56", "1.234,56", "1 234,56", "1\u{00A0}234.56", "1234.56"])
    func moneyFieldPreservesPastedAmounts(input: String) {
        #expect(Validation.moneyAmount(from: input) == Decimal(string: "1234.56"))
    }

    @Test func moneyFieldAcceptsCentsAndMaximum() {
        #expect(Validation.moneyAmount(from: "0,01") == Decimal(string: "0.01"))
        #expect(Validation.moneyAmount(from: ".5") == Decimal(string: "0.5"))
        #expect(Validation.moneyAmount(from: "1000000000") == Limits.maxAmount)
        #expect(Validation.moneyAmount(from: "1000000000.01") == nil)
    }

    @Test func unicodeLimitsMatchServerWithoutSplittingCharacters() {
        let family = "👨‍👩‍👧‍👦"
        let name = String(repeating: family, count: 4)
        #expect(!SyncValidation.isValidClient(name: name, colorHex: "#112233"))
        #expect(Validation.capped(name, max: 24) == String(repeating: family, count: 3))
        #expect(Validation.capped("e\u{301}🇬🇧", max: 3) == "e\u{301}")
        #expect(SyncValidation.isValidClient(name: Validation.capped(name, max: 24), colorHex: "#112233"))
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

    @Test func detectsSupabaseSecretKeyPrefixes() {
        #expect(SupabaseKeyValidation.looksLikeSecretKey("sb_secret_live_value"))
        #expect(!SupabaseKeyValidation.looksLikeSecretKey("sb_publishable_test_value"))
    }

    @Test func detectsServiceRoleJWTs() {
        let serviceRolePayload = "eyJyb2xlIjoic2VydmljZV9yb2xlIn0"
        #expect(SupabaseKeyValidation.looksLikeSecretKey("header.\(serviceRolePayload).signature"))
    }
}
