import Foundation
import CoreGraphics

/// Geometry and semantic identity only; never consumes editor contents.
public enum ComposerSelection {
    public struct Candidate {
        public let index: Int
        public let frame: CGRect
        public let proseMirror: Bool
        public let multiline: Bool
        public init(index: Int, frame: CGRect, proseMirror: Bool, multiline: Bool) {
            self.index = index; self.frame = frame; self.proseMirror = proseMirror; self.multiline = multiline
        }
    }
    public static func select(_ candidates: [Candidate], window: CGRect, dictateButtons: [CGRect]) -> Int? {
        let visible: [Candidate] = candidates.filter { (item: Candidate) -> Bool in
            let intersection = item.frame.intersection(window)
            return item.frame.width > 100 && item.frame.height > 0 && !intersection.isNull
                && intersection.height > 0 && intersection.width > 100
        }
        let semantic = visible.filter { $0.proseMirror }
        if semantic.count == 1 { return semantic[0].index }
        // Writing blocks may also be ProseMirror editors. The task composer sits
        // immediately above its own dictation toolbar, within the same column.
        if dictateButtons.count == 1 {
            let button = dictateButtons[0]
            let pool = semantic.isEmpty ? visible.filter { $0.multiline } : semantic
            let nearby = pool.filter { (item: Candidate) -> Bool in
                let frame = item.frame
                return frame.minY < button.midY && abs(button.minY - frame.maxY) < 200
                    && button.midX > frame.minX - 100 && button.midX < frame.maxX + 100
            }.sorted { abs(button.minY - $0.frame.maxY) < abs(button.minY - $1.frame.maxY) }
            if let first = nearby.first,
               nearby.count == 1 || abs(button.minY - nearby[1].frame.maxY) - abs(button.minY - first.frame.maxY) > 8 {
                return first.index
            }
        }
        let multiline = visible.filter { $0.multiline }
        return semantic.isEmpty && multiline.count == 1 ? multiline[0].index : nil
    }
}
