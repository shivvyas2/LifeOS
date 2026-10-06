import Testing
import Foundation
@testable import DesignSystem

@Suite struct DotGridTests {
    @Test func anyRealDayOpensIncludingOnesAhead() {
        let day = Date()
        #expect(DotGrid.isOpenable(DotCell(id: 1, date: day, state: .future)))
        #expect(DotGrid.isOpenable(DotCell(id: 2, date: day, state: .onTarget)))
        #expect(DotGrid.isOpenable(DotCell(id: 3, date: day, state: .today)))
        #expect(!DotGrid.isOpenable(DotCell(id: 4, date: nil, state: .blank)))
        #expect(!DotGrid.isOpenable(DotCell(id: 5, date: day, state: .blank)))
    }
}
