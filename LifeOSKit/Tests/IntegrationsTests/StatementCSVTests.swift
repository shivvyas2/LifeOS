import Testing
import Foundation
import Persistence
@testable import Integrations

@Suite struct StatementCSVTests {
    @Test func chaseSignsPurchasesNegativeAndDropsThePayment() throws {
        let csv = """
        Transaction Date,Post Date,Description,Category,Type,Amount,Memo
        10/02/2026,10/03/2026,STARBUCKS STORE 123,Food & Drink,Sale,-6.45,
        10/01/2026,10/02/2026,AMAZON MKTPL,Shopping,Return,12.00,
        09/30/2026,09/30/2026,Payment Thank You-Mobile,,Payment,500.00,
        """
        let lines = try StatementCSV.parse(csv)
        #expect(lines.count == 2)
        #expect(lines[0].merchant == "STARBUCKS STORE 123")
        #expect(lines[0].cents == -645)
        #expect(lines[1].cents == 1200)
    }

    @Test func discoverSignsPurchasesPositive() throws {
        let csv = """
        Trans. Date,Post Date,Description,Amount,Category
        10/02/2026,10/02/2026,"TRADER JOE'S #552, SF",54.21,Supermarkets
        10/03/2026,10/03/2026,SHELL OIL,40.00,Gasoline
        10/04/2026,10/04/2026,INTERNET PAYMENT - THANK YOU,-300.00,Payments and Credits
        """
        let lines = try StatementCSV.parse(csv)
        #expect(lines.map(\.cents) == [-5421, -4000])
        #expect(lines[0].merchant == "TRADER JOE'S #552, SF")
    }

    @Test func appleCardUsesItsTypeColumn() throws {
        let csv = """
        Transaction Date,Clearing Date,Description,Merchant,Category,Type,Amount (USD),Purchased By
        10/05/2026,10/06/2026,UBER *TRIP,Uber,Transportation,Purchase,18.20,Shiv
        10/06/2026,10/06/2026,ACH DEPOSIT,Payment,Payment,Payment,-200.00,Shiv
        """
        let lines = try StatementCSV.parse(csv)
        #expect(lines.count == 1)
        #expect(lines[0].cents == -1820)
    }

    @Test func debitAndCreditColumns() throws {
        let csv = """
        Transaction Date,Posted Date,Card No.,Description,Category,Debit,Credit
        2026-10-01,2026-10-02,4821,WHOLE FOODS,Grocery,82.10,
        2026-10-02,2026-10-03,4821,REFUND STORE,Other,,15.00
        """
        let lines = try StatementCSV.parse(csv)
        #expect(lines.map(\.cents) == [-8210, 1500])
    }

    @Test func aFileWithNoUsableHeaderIsRefused() {
        #expect(throws: StatementCSV.Failure.unrecognisedColumns) {
            try StatementCSV.parse("hello,world\n1,2")
        }
    }

    @Test func numbersInEveryBankSpelling() {
        #expect(StatementCSV.number("$1,234.56") == 1234.56)
        #expect(StatementCSV.number("(45.00)") == -45)
        #expect(StatementCSV.number("12.30 CR") == -12.30)
        #expect(StatementCSV.number("") == nil)
    }

    @Test func quotedFieldsKeepTheirCommasAndQuotes() {
        let records = StatementCSV.records("a,\"b, c\",\"say \"\"hi\"\"\"\n1,2,3")
        #expect(records == [["a", "b, c", "say \"hi\""], ["1", "2", "3"]])
    }
}
