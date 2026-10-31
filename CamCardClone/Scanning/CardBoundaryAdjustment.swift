import CoreGraphics
import Foundation

/// 名片四边形的四个角，供手动调整时定位拖拽手柄。
///
/// 顺序与 `CardQuad` 一致：顺时针，起点在左上（y 轴向上的坐标系里「上」是较大的 y）。
enum CardQuadCorner: String, CaseIterable, Equatable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

/// 手动调整名片边界的编辑状态。
///
/// 规格 `Card boundary detection` 要求「当自动检测结果不可靠时允许用户手动调整或重拍」，
/// 本类型只承担**几何层**的编辑语义（拖到哪、是否还合法），不含任何手势识别与界面代码，
/// 因此可以在没有模拟器、没有真机的环境里断言。
///
/// 与自动检测的取舍不同：手动框豁免「面积过小」与「长宽比不像名片」两项启发式——
/// 它们本来是给机器判可信度用的，而人已经看过照片并亲自指出名片在哪，画得比自动框小是合理的；
/// 但**面积上限仍然保留**，用于守住规格明令的「不得把整张图片当作名片」。
struct CardBoundaryAdjustment: Equatable {

    /// 进入手动调整时的起点框。
    let initialQuad: CardQuad
    /// 当前（可被拖动的）框。
    private(set) var quad: CardQuad

    /// 找不到候选区域时给出的默认框：画面居中、约占 76% × 48%，长宽比约 1.58，形如横版名片。
    static let defaultQuad = CardQuad(
        topLeft: CGPoint(x: 0.12, y: 0.74),
        topRight: CGPoint(x: 0.88, y: 0.74),
        bottomRight: CGPoint(x: 0.88, y: 0.26),
        bottomLeft: CGPoint(x: 0.12, y: 0.26)
    )

    /// 手动框的最小归一化面积：比自动检测的 0.12 宽松得多（照片里名片可以只占一小块），
    /// 仅用于拦住被拖成一条线或一个点的退化框。
    static let minimumArea: CGFloat = 0.02

    /// 手动框的最大归一化面积：沿用自动检测的上限，避免把整张图片当作名片。
    static let maximumArea: CGFloat = 0.98

    /// 拖拽命中的默认半径（归一化坐标）。
    static let defaultHitRadius: CGFloat = 0.06

    init(quad: CardQuad) {
        self.initialQuad = quad
        self.quad = quad
    }

    /// 由一次检测结果得到调整起点：候选框直接沿用，找不到候选时用默认框。
    static func starting(from outcome: CardDetectionOutcome) -> CardBoundaryAdjustment {
        switch outcome {
        case .detected(let quad), .unreliable(let quad):
            return CardBoundaryAdjustment(quad: quad)
        case .notFound:
            return CardBoundaryAdjustment(quad: defaultQuad)
        }
    }

    // MARK: - 读取

    /// 某个角当前的位置。
    func position(of corner: CardQuadCorner) -> CGPoint {
        switch corner {
        case .topLeft: return quad.topLeft
        case .topRight: return quad.topRight
        case .bottomRight: return quad.bottomRight
        case .bottomLeft: return quad.bottomLeft
        }
    }

    /// 拖拽命中测试：返回半径内距离最近的角；都不在半径内返回 `nil`。
    func hitTest(_ point: CGPoint, radius: CGFloat = CardBoundaryAdjustment.defaultHitRadius) -> CardQuadCorner? {
        var best: (corner: CardQuadCorner, distance: CGFloat)?
        for corner in CardQuadCorner.allCases {
            let distance = Self.distance(point, position(of: corner))
            guard distance <= radius else { continue }
            if let current = best, current.distance <= distance { continue }
            best = (corner, distance)
        }
        return best?.corner
    }

    /// 当前框能否送去校正。
    ///
    /// 三条要求：四个角依次连成**凸**四边形（拖过头会让它自交或凹进去，透视校正对那种框没有意义）、
    /// 有向面积为正（角顺序未被拖反）、面积落在 `minimumArea…maximumArea` 内。
    var isUsable: Bool {
        quad.signedArea > 0 && Self.isConvexClockwise(quad)
            && quad.area >= Self.minimumArea && quad.area <= Self.maximumArea
    }

    /// 是否已经被拖动过（用于界面显示「已按你的调整校正」）。
    var isModified: Bool {
        quad != initialQuad
    }

    // MARK: - 编辑

    /// 把某个角移动到归一化坐标 `point`（越界自动夹到 0…1 内）。
    mutating func move(_ corner: CardQuadCorner, to point: CGPoint) {
        let clamped = Self.clamp(point)
        switch corner {
        case .topLeft: quad = quad.replacing(topLeft: clamped)
        case .topRight: quad = quad.replacing(topRight: clamped)
        case .bottomRight: quad = quad.replacing(bottomRight: clamped)
        case .bottomLeft: quad = quad.replacing(bottomLeft: clamped)
        }
    }

    /// 手势拖动：在当前位置上叠加位移（同样夹在 0…1 内）。
    mutating func offset(_ corner: CardQuadCorner, by delta: CGSize) {
        let current = position(of: corner)
        move(corner, to: CGPoint(x: current.x + delta.width, y: current.y + delta.height))
    }

    /// 回到起点框。
    mutating func reset() {
        quad = initialQuad
    }

    // MARK: - 内部

    private static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: Swift.min(Swift.max(point.x, 0), 1), y: Swift.min(Swift.max(point.y, 0), 1))
    }

    /// 四个角是否按顺时针连成一个凸四边形。
    ///
    /// y 轴向上的坐标系里，顺时针四边形的任意连续三点叉积同号（本项目的角序下为负）；
    /// 出现异号说明某个角被拖到了另外三个角围成的三角形内部（凹）或与对边交叉（自交）。
    private static func isConvexClockwise(_ quad: CardQuad) -> Bool {
        let points = quad.corners
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let cross = (current.x - previous.x) * (next.y - current.y)
                - (current.y - previous.y) * (next.x - current.x)
            guard cross < 0 else { return false }
        }
        return true
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let deltaX = lhs.x - rhs.x
        let deltaY = lhs.y - rhs.y
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }
}

private extension CardQuad {
    /// 逐角替换，保持 `CardQuad` 的不可变语义。
    func replacing(
        topLeft: CGPoint? = nil,
        topRight: CGPoint? = nil,
        bottomRight: CGPoint? = nil,
        bottomLeft: CGPoint? = nil
    ) -> CardQuad {
        CardQuad(
            topLeft: topLeft ?? self.topLeft,
            topRight: topRight ?? self.topRight,
            bottomRight: bottomRight ?? self.bottomRight,
            bottomLeft: bottomLeft ?? self.bottomLeft
        )
    }
}
