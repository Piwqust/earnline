import Security
import Testing
@testable import earnline

struct EarnlineAuthStorageTests {
    @Test func simulatorWithoutAKeychainEntitlementStartsSignedOut() {
        #if targetEnvironment(simulator)
        #expect(EarnlineAuthStorage.isAbsentSessionStatus(errSecItemNotFound))
        #expect(EarnlineAuthStorage.isAbsentSessionStatus(errSecMissingEntitlement))
        #else
        #expect(EarnlineAuthStorage.isAbsentSessionStatus(errSecItemNotFound))
        #expect(!EarnlineAuthStorage.isAbsentSessionStatus(errSecMissingEntitlement))
        #endif
    }
}
