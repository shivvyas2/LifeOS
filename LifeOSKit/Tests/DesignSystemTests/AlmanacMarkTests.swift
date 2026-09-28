import Testing
import SwiftUI
@testable import DesignSystem

@Suite struct AlmanacMarkTests {
    @Test func leavesStackFromTopToBottomOnTheCentreLine() {
        let g = AlmanacMarkGeometry(side: 1024, inTile: true)
        let ys = AlmanacMarkGeometry.Leaf.allCases.map { g.leafCenter($0).y }
        #expect(ys == ys.sorted())
        #expect(AlmanacMarkGeometry.Leaf.allCases.allSatisfy { g.leafCenter($0).x == 512 })
    }

    @Test func theStackStaysInsideTheBoxInBothLayouts() {
        for inTile in [true, false] {
            let g = AlmanacMarkGeometry(side: 200, inTile: inTile)
            let bounds = AlmanacMarkGeometry.Leaf.allCases.map { g.leaf($0).boundingRect }.reduce(CGRect.null) { $0.union($1) }
            #expect(bounds.minX >= 0 && bounds.minY >= 0, "\(inTile) \(bounds)")
            #expect(bounds.maxX <= 200 && bounds.maxY <= 200, "\(inTile) \(bounds)")
        }
    }

    @Test func theTransparentMarkIsVerticallyCentred() {
        let g = AlmanacMarkGeometry(side: 1024, inTile: false)
        let bounds = AlmanacMarkGeometry.Leaf.allCases.map { g.leaf($0).boundingRect }.reduce(CGRect.null) { $0.union($1) }
        #expect(abs(bounds.midY - 512) < 8, "\(bounds)")
    }

    @Test func theOrbSitsOnTheTopLeaf() {
        let g = AlmanacMarkGeometry(side: 1024, inTile: true)
        #expect(g.leaf(.top).boundingRect.contains(g.orbCenter))
        #expect(g.leaf(.top).boundingRect.contains(g.crescentCenter))
    }

    @Test func geometryScalesLinearly() {
        let big = AlmanacMarkGeometry(side: 1024, inTile: true), small = AlmanacMarkGeometry(side: 256, inTile: true)
        #expect(big.orbCenter.x == small.orbCenter.x * 4)
        #expect(big.leaf(.middle).boundingRect.width == small.leaf(.middle).boundingRect.width * 4)
    }
}
