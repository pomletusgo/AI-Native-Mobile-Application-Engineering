import CoreGraphics
import Foundation

/// 归一化坐标下的名片四边形。
///
/// 四个角按顺时针给出，坐标原点在左下角（与 Vision 一致），取值范围 0…1。
struct CardQuad: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    /// 顺时针顺序的四个角。
    var corners: [CGPoint] {
        [topLeft, topRight, bottomRight, bottomLeft]
    }

    /// 有向面积。`corners` 按 topLeft → topRight → bottomRight → bottomLeft 给出，
    /// 在 y 轴向上的坐标系里是顺时针，鞋带公式本身对逆时针为正，故取负号使顺时针为正；
    /// 负值表示四个角的顺序反了。
    var signedArea: CGFloat {
        let points = corners
        var total: CGFloat = 0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            total += current.x * next.y - next.x * current.y
        }
        return -total / 2
    }

    /// 归一化面积（0…1）。
    var area: CGFloat {
        abs(signedArea)
    }

    /// 长边 ÷ 短边，在**像素空间**计算；退化四边形返回 0。
    ///
    /// 必须换算到像素再算：归一化坐标的 x、y 尺度不同（分别除以图宽、图高），直接拿归一化
    /// 角点算比例会被图片宽高比压扁——1400×900 的横版照片里，真实比例 1.667 的名片只剩
    /// 1.072，会被下面的长宽比判据整批判成「不像名片」（2026-11-01 由 `testDiagnoseCorpusDetection`
    /// 在 CI 上实测：30 张合成语料的像素长宽比 1.59…1.69，归一化口径下却只有 1.03…1.08）。
    /// 归一化面积 `area` 不受此影响——它本来就是「占整幅图的比例」，与图片形状无关。
    func aspectRatio(in imageSize: CGSize) -> CGFloat {
        let corners = pixelCorners(in: imageSize)
        let edges = [
            Self.distance(corners.topLeft, corners.topRight),
            Self.distance(corners.bottomLeft, corners.bottomRight),
            Self.distance(corners.topLeft, corners.bottomLeft),
            Self.distance(corners.topRight, corners.bottomRight)
        ]
        guard let longEdge = edges.max(), let shortEdge = edges.min(), shortEdge > 0 else {
            return 0
        }
        return longEdge / shortEdge
    }

    /// 检测结果是否可用。
    ///
    /// 规格要求「检测结果不可靠时允许用户手动调整或重拍，不得把整张图片当作名片」，
    /// 因此这里排除三类候选：面积过小（多半是误检的局部纹理）、几乎覆盖整张图
    /// （多半把背景或整幅画的边界当成了名片）、长宽比不像名片（多半是桌面或屏幕边框）。
    /// `imageSize` 传原图的像素尺寸，长宽比判据要靠它换算到像素空间（见 `aspectRatio(in:)`）。
    /// 阈值为常见名片比例给出的初值，需在真实照片样本上复核。
    func isReliable(
        in imageSize: CGSize,
        minArea: CGFloat = 0.12,
        maxArea: CGFloat = 0.98,
        aspectRange: ClosedRange<CGFloat> = 1.15...3.6
    ) -> Bool {
        let covered = area
        guard covered >= minArea, covered <= maxArea else { return false }
        return aspectRange.contains(aspectRatio(in: imageSize))
    }

    /// 映射到图片像素坐标（原点仍在左下角，供 Core Image 使用）。
    func pixelCorners(in imageSize: CGSize) -> (
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) {
        func scaled(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
        }
        return (scaled(topLeft), scaled(topRight), scaled(bottomRight), scaled(bottomLeft))
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }
}

/// 区域检测的三种结果。
enum CardDetectionOutcome: Equatable {
    /// 检测到候选区域且判定可用，可直接进入校正。
    case detected(CardQuad)
    /// 检测到候选区域但不可靠（面积过小、几乎覆盖整张图或长宽比异常），需要人工调整或重拍。
    case unreliable(CardQuad)
    /// 图片里找不到候选名片区域，需要重拍或手动调整。
    case notFound
}

/// 区域检测与校正过程中可预期的失败。
enum CardBoundaryError: LocalizedError, Equatable {
    /// 图片数据无法解码成图像。
    case invalidImageData
    /// 检测引擎本身报错。
    case detectionFailed(reason: String)
    /// 透视或方向校正失败。
    case correctionFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "无法读取图片，请重新拍摄或选择图片。"
        case .detectionFailed(let reason):
            return "名片区域检测失败：\(reason)"
        case .correctionFailed(let reason):
            return "名片校正失败：\(reason)"
        }
    }
}

/// 名片区域检测能力。具体实现见 `VisionCardBoundaryDetector`。
protocol CardBoundaryDetecting: AnyObject {
    /// 检测图片中的名片区域。找不到或判定不可靠时不抛错，而是返回对应的 `CardDetectionOutcome`，
    /// 让上层走「重拍或手动调整」而不是中断流程。
    func detectCard(in imageData: Data) async throws -> CardDetectionOutcome
}
