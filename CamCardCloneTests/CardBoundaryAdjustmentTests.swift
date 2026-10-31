import CoreGraphics
import XCTest
@testable import CamCardClone

/// `CardBoundaryAdjustment` 单元测试。
///
/// 覆盖 P03 的「手动调整边界」几何层：起点选取、拖拽与夹紧、命中测试、合法性判定与重置。
/// 这些是手势背后的纯逻辑，不依赖模拟器与真机；真实拖拽手感与检测框叠加显示属人工验收
/// （见 `docs/UI验收清单.md` M18 / M22）。
final class CardBoundaryAdjustmentTests: XCTestCase {

    /// 常见名片比例（0.8 × 0.48，长宽比约 1.67），可被自动检测判为可靠。
    private var reliableQuad: CardQuad {
        CardQuad(
            topLeft: CGPoint(x: 0.10, y: 0.74),
            topRight: CGPoint(x: 0.90, y: 0.74),
            bottomRight: CGPoint(x: 0.90, y: 0.26),
            bottomLeft: CGPoint(x: 0.10, y: 0.26)
        )
    }

    /// 面积仅 0.0015 的候选，自动检测会判为不可靠。
    private var tinyQuad: CardQuad {
        CardQuad(
            topLeft: CGPoint(x: 0.40, y: 0.43),
            topRight: CGPoint(x: 0.45, y: 0.43),
            bottomRight: CGPoint(x: 0.45, y: 0.40),
            bottomLeft: CGPoint(x: 0.40, y: 0.40)
        )
    }

    /// 0.5 × 0.1 的细长框：面积 0.05、长宽比 5.0，两项都被自动判定排除，但人手动圈出是合理的。
    private var smallThinQuad: CardQuad {
        CardQuad(
            topLeft: CGPoint(x: 0.20, y: 0.65),
            topRight: CGPoint(x: 0.70, y: 0.65),
            bottomRight: CGPoint(x: 0.70, y: 0.55),
            bottomLeft: CGPoint(x: 0.20, y: 0.55)
        )
    }

    // MARK: - 起点选取

    func testStartingFromDetectedUsesDetectedQuad() {
        let adjustment = CardBoundaryAdjustment.starting(from: .detected(reliableQuad))

        XCTAssertEqual(adjustment.initialQuad, reliableQuad)
        XCTAssertEqual(adjustment.quad, reliableQuad)
        XCTAssertFalse(adjustment.isModified)
    }

    func testStartingFromUnreliableKeepsCandidateInsteadOfDiscardingIt() {
        let adjustment = CardBoundaryAdjustment.starting(from: .unreliable(tinyQuad))

        XCTAssertEqual(adjustment.initialQuad, tinyQuad, "被判为不可靠的框仍应作为调整起点，让用户接着改")
        XCTAssertEqual(adjustment.quad, tinyQuad)
    }

    func testStartingFromNotFoundUsesCenteredDefaultQuad() {
        let adjustment = CardBoundaryAdjustment.starting(from: .notFound)

        XCTAssertEqual(adjustment.quad, CardBoundaryAdjustment.defaultQuad)
    }

    func testDefaultQuadIsCenteredAndUsable() {
        let quad = CardBoundaryAdjustment.defaultQuad

        XCTAssertEqual(quad.topLeft.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(quad.topRight.x, 0.88, accuracy: 0.0001)
        XCTAssertEqual(quad.bottomRight.y, 0.26, accuracy: 0.0001)
        XCTAssertEqual(quad.topLeft.y, 0.74, accuracy: 0.0001)
        XCTAssertTrue(CardBoundaryAdjustment(quad: quad).isUsable)
    }

    // MARK: - 拖拽与夹紧

    func testMoveUpdatesOnlyTheGivenCorner() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)

        adjustment.move(.topLeft, to: CGPoint(x: 0.20, y: 0.80))

        XCTAssertEqual(adjustment.position(of: .topLeft), CGPoint(x: 0.20, y: 0.80))
        XCTAssertEqual(adjustment.position(of: .topRight), reliableQuad.topRight)
        XCTAssertEqual(adjustment.position(of: .bottomRight), reliableQuad.bottomRight)
        XCTAssertEqual(adjustment.position(of: .bottomLeft), reliableQuad.bottomLeft)
        XCTAssertTrue(adjustment.isModified)
    }

    func testMoveClampsToUnitSquare() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)

        adjustment.move(.topLeft, to: CGPoint(x: -0.5, y: 1.8))

        XCTAssertEqual(adjustment.position(of: .topLeft), CGPoint(x: 0, y: 1))
        XCTAssertEqual(adjustment.position(of: .bottomRight), reliableQuad.bottomRight, "其余角不受影响")
    }

    func testOffsetAccumulatesFromCurrentPosition() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)

        adjustment.offset(.bottomRight, by: CGSize(width: -0.05, height: 0.04))
        adjustment.offset(.bottomRight, by: CGSize(width: -0.05, height: 0.04))

        XCTAssertEqual(adjustment.position(of: .bottomRight), CGPoint(x: 0.80, y: 0.34))
    }

    func testOffsetClampsAfterRepeatedDrags() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)

        for _ in 0..<10 {
            adjustment.offset(.topLeft, by: CGSize(width: -0.5, height: 0.5))
        }

        XCTAssertEqual(adjustment.position(of: .topLeft), CGPoint(x: 0, y: 1))
    }

    // MARK: - 命中测试

    func testHitTestReturnsCornerWithinRadius() {
        let adjustment = CardBoundaryAdjustment(quad: reliableQuad)

        XCTAssertEqual(adjustment.hitTest(CGPoint(x: 0.11, y: 0.75)), .topLeft)
        XCTAssertEqual(adjustment.hitTest(CGPoint(x: 0.89, y: 0.25)), .bottomRight)
    }

    func testHitTestReturnsNilWhenNoCornerIsNear() {
        let adjustment = CardBoundaryAdjustment(quad: reliableQuad)

        XCTAssertNil(adjustment.hitTest(CGPoint(x: 0.50, y: 0.50)), "画面中心离四个角都远，不应命中")
    }

    func testHitTestPrefersTheNearestCorner() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        // 把左上角拖到右上角附近，两个角都落在半径内，应命中的是更近的左上角。
        adjustment.move(.topLeft, to: CGPoint(x: 0.86, y: 0.72))

        XCTAssertEqual(adjustment.hitTest(CGPoint(x: 0.85, y: 0.71)), .topLeft)
        XCTAssertEqual(adjustment.hitTest(CGPoint(x: 0.895, y: 0.75)), .topRight)
    }

    func testHitTestRadiusIsRespected() {
        let adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        let point = CGPoint(x: 0.18, y: 0.74)

        XCTAssertNil(adjustment.hitTest(point, radius: 0.02))
        XCTAssertEqual(adjustment.hitTest(point, radius: 0.10), .topLeft)
    }

    // MARK: - 合法性

    func testReliableQuadIsUsable() {
        XCTAssertTrue(CardBoundaryAdjustment(quad: reliableQuad).isUsable)
    }

    func testQuadSmallerThanAutoThresholdIsStillUsable() {
        XCTAssertFalse(smallThinQuad.isReliable(), "面积与长宽比都被自动判定排除")
        XCTAssertTrue(CardBoundaryAdjustment(quad: smallThinQuad).isUsable, "人手动圈出的框不再受自动启发式约束")
    }

    func testSquareQuadIsUsableEvenThoughAspectRatioIsNotCardLike() {
        let square = CardQuad(
            topLeft: CGPoint(x: 0.25, y: 0.75),
            topRight: CGPoint(x: 0.75, y: 0.75),
            bottomRight: CGPoint(x: 0.75, y: 0.25),
            bottomLeft: CGPoint(x: 0.25, y: 0.25)
        )

        XCTAssertFalse(square.isReliable(), "长宽比 1.0 不像名片，自动检测不应采信")
        XCTAssertTrue(CardBoundaryAdjustment(quad: square).isUsable)
    }

    func testFullFrameQuadIsRejectedEvenThoughUserDrewIt() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        adjustment.move(.topLeft, to: CGPoint(x: 0, y: 1))
        adjustment.move(.topRight, to: CGPoint(x: 1, y: 1))
        adjustment.move(.bottomRight, to: CGPoint(x: 1, y: 0))
        adjustment.move(.bottomLeft, to: CGPoint(x: 0, y: 0))

        XCTAssertFalse(adjustment.isUsable, "规格禁止把整张图片当作名片")
        XCTAssertFalse(adjustment.quad.isReliable())
    }

    func testConcaveQuadIsRejected() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        // 把左上角拖进另外三个角围成的三角形内部，四边形凹进去，透视校正没有意义。
        adjustment.move(.topLeft, to: CGPoint(x: 0.60, y: 0.40))

        XCTAssertFalse(adjustment.isUsable)
    }

    func testCornerDraggedAcrossTheOppositeCornerIsRejected() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        // 把左上角拖到左下角下方，四个角的顺序被拖反。
        adjustment.move(.topLeft, to: CGPoint(x: 0.10, y: 0.10))

        XCTAssertFalse(adjustment.isUsable)
    }

    func testCollapsedQuadIsRejected() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        adjustment.move(.topLeft, to: CGPoint(x: 0.10, y: 0.50))
        adjustment.move(.topRight, to: CGPoint(x: 0.90, y: 0.50))
        adjustment.move(.bottomRight, to: CGPoint(x: 0.90, y: 0.50))
        adjustment.move(.bottomLeft, to: CGPoint(x: 0.10, y: 0.50))

        XCTAssertFalse(adjustment.isUsable, "被拖成一条线的框面积为零")
    }

    // MARK: - 重置

    func testResetRestoresInitialQuad() {
        var adjustment = CardBoundaryAdjustment(quad: reliableQuad)
        adjustment.move(.topLeft, to: CGPoint(x: 0.30, y: 0.90))
        adjustment.move(.bottomRight, to: CGPoint(x: 0.70, y: 0.10))
        XCTAssertTrue(adjustment.isModified)

        adjustment.reset()

        XCTAssertEqual(adjustment.quad, reliableQuad)
        XCTAssertFalse(adjustment.isModified)
    }
}
