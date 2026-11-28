import Foundation

/// 拖动中保持原始布局，用整个条目的位移预览排序，松手后才写回条目顺序。
struct DragReorderLayout {
    let source: Int
    let target: Int
    let translation: CGFloat
    private let displacedHeight: CGFloat

    init?(source: Int, translation: CGFloat, heights: [CGFloat], spacing: CGFloat = 14) {
        guard heights.indices.contains(source), translation.isFinite, spacing.isFinite, spacing >= 0,
              heights.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        self.source = source; self.translation = translation
        displacedHeight = heights[source] + spacing
        var target = source, distance: CGFloat = 0
        let neighbors = translation >= 0 ? Array((source + 1) ..< heights.count) : Array((0 ..< source).reversed())
        for index in neighbors {
            let extent = heights[index] + spacing
            guard abs(translation) > distance + extent / 2 else { break }
            target = index; distance += extent
        }
        self.target = target
    }

    func offset(at index: Int) -> CGFloat {
        if index == source { return translation }
        if source < index && index <= target { return -displacedHeight }
        if target <= index && index < source { return displacedHeight }
        return 0
    }
}
