import Foundation

public enum RecordingVisibility {
    public enum Action: Equatable { case stayActive, finishAndSuspend, disconnect }
    public static func onHide(locked: Bool, recording: Bool, stopping: Bool) -> Action {
        if locked && recording { return .stayActive }
        if recording || stopping { return .finishAndSuspend }
        return .disconnect
    }
}
