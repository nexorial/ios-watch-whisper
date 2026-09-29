import XCTest
@testable import MicodexCore

final class SetupReadinessTests: XCTestCase {
    private let ready = SetupReadiness(driverAvailable: true, inputSelected: true,
                                      accessibilityAllowed: true, receiverReady: true, watchPaired: true)

    func testDetectedDevicesAndPairingCannotClaimTranscriptionSuccess() {
        XCTAssertFalse(ready.canFinish(voiceEnabled: true, scrollingConfirmed: true, transcriptionConfirmed: false))
        XCTAssertFalse(ready.canFinish(voiceEnabled: true, scrollingConfirmed: false, transcriptionConfirmed: true))
        XCTAssertTrue(ready.canFinish(voiceEnabled: true, scrollingConfirmed: true, transcriptionConfirmed: true))
    }

    func testEachMissingLocalRequirementBlocksVoiceCompletion() {
        for key in [\SetupReadiness.driverAvailable, \.inputSelected, \.accessibilityAllowed, \.receiverReady, \.watchPaired] {
            var state = ready
            state[keyPath: key] = false
            XCTAssertFalse(state.canFinish(voiceEnabled: true, scrollingConfirmed: true, transcriptionConfirmed: true))
        }
    }

    func testScrollingOnlyDoesNotRequireAnAudioDriverOrMicrophoneTest() {
        var state = ready
        state.driverAvailable = false; state.inputSelected = false
        XCTAssertTrue(state.canFinish(voiceEnabled: false, scrollingConfirmed: true, transcriptionConfirmed: false))
        state.accessibilityAllowed = false
        XCTAssertFalse(state.canFinish(voiceEnabled: false, scrollingConfirmed: true, transcriptionConfirmed: false))
    }

    func testPermissionRevocationOrNetworkLossInvalidatesPreviouslyReadySetup() {
        var state = ready
        XCTAssertTrue(state.canFinish(voiceEnabled: true, scrollingConfirmed: true, transcriptionConfirmed: true))
        state.receiverReady = false
        XCTAssertFalse(state.canFinish(voiceEnabled: true, scrollingConfirmed: true, transcriptionConfirmed: true))
        state.receiverReady = true; state.inputSelected = false
        XCTAssertFalse(state.canFinish(voiceEnabled: true, scrollingConfirmed: true, transcriptionConfirmed: true))
    }
}
