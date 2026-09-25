import Foundation

/// Inspected in the installed Codex bundle on 2026-09-25. Exact matching avoids
/// accidentally pressing voice-call, task-stop, or 'Transcribe and send' controls.
public enum AgentLabels {
    public static let dictate: Set<String> = ["Dictate", "听写", "口述"]
    public static let stop: Set<String> = ["Stop dictation", "停止听写", "停止口述"]
    public static let cancel: Set<String> = ["Cancel dictation", "取消听写", "取消口述"]
    public static let transcribing: Set<String> = ["Finishing dictation", "正在完成听写", "正在完成口述", "Cancel transcription", "取消转写", "取消转录"]
    public static let starting: Set<String> = ["Starting dictation; click to cancel", "正在启动听写；点击可取消", "正在开始听写；点击可取消"]
}
