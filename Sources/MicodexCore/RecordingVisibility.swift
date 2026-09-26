import Foundation

public enum RecordingVisibility {
    public enum Action: Equatable { case stayActive, finishAndSuspend, disconnect }
    public static func onHide(locked: Bool, recording: Bool, stopping: Bool) -> Action {
        if stopping { return .finishAndSuspend }
        if locked && recording { return .stayActive }
        if recording { return .finishAndSuspend }
        return .disconnect
    }
}
