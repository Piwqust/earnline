import SwiftUI
import Testing
@testable import earnline

@MainActor
struct AuthTourDirectorTests {
    actor RecordingSleeper: AuthTourSleeping {
        private var recordedDurations: [Duration] = []

        func sleep(for duration: Duration) async throws {
            recordedDurations.append(duration)
        }

        func count() -> Int { recordedDurations.count }
        func durations() -> [Duration] { recordedDurations }
    }

    @Test func directorPlaysTheSemanticBeatsThenQuietlyResets() async throws {
        let sleeper = RecordingSleeper()
        let director = try AuthTourDirector(sleeper: sleeper)

        #expect(await director.playOneCycleForTesting())
        #expect(director.beatHistory == [.ledger, .addIncome, .edit, .insights, .client, .ledger])
        #expect(director.beat == .ledger)
        #expect(director.scene.screen == .ledger)
        #expect(director.scene.scriptedLine == nil)
        #expect(director.scene.showsComposer)
        #expect(await sleeper.count() == 9)
        #expect(await sleeper.durations() == [
            .seconds(AuthTourTiming.establishingDwell),
            .seconds(AuthTourTiming.composerDwell),
            .seconds(AuthTourTiming.editorBeforePayment),
            .seconds(AuthTourTiming.editorAfterPayment),
            .seconds(AuthTourTiming.chartBeforeReveal),
            .seconds(AuthTourTiming.chartAfterReveal),
            .seconds(AuthTourTiming.clientBeforeHistory),
            .seconds(AuthTourTiming.clientAfterHistory),
            .seconds(AuthTourTiming.resetDwell),
        ])
    }

    @Test func pauseSettlesAndAForcedBeatResumesDeterministically() throws {
        let director = try AuthTourDirector()
        director.move(to: .client)
        #expect(director.scene.screen == .client)

        director.pause()
        #expect(director.playbackPolicy == .settled)
        #expect(director.scene.screen == .ledger)
        #expect(director.scene.scriptedLine != nil)
        #expect(!director.scene.showsComposer)

        director.configure(
            options: .init(forcedBeat: .edit),
            policy: .autoplay
        )
        #expect(director.beat == .edit)
        #expect(director.scene.screen == .editor)
        #expect(director.scene.editorStatus == .inProgress)
    }

    @Test func oneIncomeLineCarriesTheStoryFromLedgerToInsightAndClient() throws {
        let scene = try AuthTourScene()
        let earnedBefore = scene.currentMonthTotal

        scene.addIncomeLine()
        #expect(scene.scriptedLine?.status == .inProgress)
        // Earnline's normal monthly total includes work in progress, so the
        // tour must not invent a different accounting rule just for motion.
        #expect(scene.currentMonthTotal == earnedBefore + 240)

        scene.markIncomePaid()
        #expect(scene.currentMonthTotal == earnedBefore + 240)
        #expect(scene.monthlyTrendPoints.last?.total == earnedBefore + 240)

        scene.openClientProfile()
        #expect(scene.screen == .client)
        #expect(scene.scriptedLine?.client?.id == scene.acme.id)
    }

    @Test func staticPlaybackPolicyCoversMotionPowerAndInactiveStates() {
        #expect(AuthTourPlaybackPolicy.resolve(
            isAccountDockActive: true,
            scenePhase: .active,
            reduceMotion: false,
            playAnimatedImages: true,
            lowPowerMode: false
        ) == .autoplay)

        #expect(AuthTourPlaybackPolicy.resolve(
            isAccountDockActive: true,
            scenePhase: .active,
            reduceMotion: true,
            playAnimatedImages: true,
            lowPowerMode: false
        ) == .settled)
        #expect(AuthTourPlaybackPolicy.resolve(
            isAccountDockActive: true,
            scenePhase: .active,
            reduceMotion: false,
            playAnimatedImages: false,
            lowPowerMode: false
        ) == .settled)
        #expect(AuthTourPlaybackPolicy.resolve(
            isAccountDockActive: true,
            scenePhase: .active,
            reduceMotion: false,
            playAnimatedImages: true,
            lowPowerMode: true
        ) == .settled)
        #expect(AuthTourPlaybackPolicy.resolve(
            isAccountDockActive: true,
            scenePhase: .inactive,
            reduceMotion: false,
            playAnimatedImages: true,
            lowPowerMode: false
        ) == .settled)
    }
}
