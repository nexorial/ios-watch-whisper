import Foundation

public enum RecordingVisibility {
    public enum Action: Equatable { case stayActive, finishAndSuspend, disconnect }
    public static func onHide(recording: Bool, stopping: Bool) -> Action {
        if stopping { return .finishAndSuspend }
        if recording { return .stayActive }
        return .disconnect
    }
}
