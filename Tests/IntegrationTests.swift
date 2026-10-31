import XCTest
@testable import Financeiro

final class CSVImporterTests: XCTestCase {
    func testBOMQuotesEscapesMultilineAndCRLF() throws {
        let csv = "\u{FEFF}date;merchant;amount;kind;note\r\n" +
            "2026-10-31T12:30:00-03:00;\"Mercado; \"\"Centro\"\"\";12,34;expense;\"linha 1\r\nlinha 2\"\r\n"
        let parsed = try CSVImporter.parse(csv)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].merchant, "Mercado; \"Centro\"")
        XCTAssertEqual(parsed[0].amountMinor, 1_234)
        XCTAssertEqual(parsed[0].note, "linha 1\r\nlinha 2")
        XCTAssertEqual(parsed[0].source, .imported)
    }

    func testCommaDelimiterRequiresQuotedBrazilianDecimal() throws {
        let csv = "date,merchant,amount,kind\n2026-10-31T12:30:00Z,Mercado,\"1.234,56\",expense\n"
        XCTAssertEqual(try CSVImporter.parse(csv).first?.amountMinor, 123_456)
    }

    func testRepeatedPurchasesKeepDistinctIDsAndReimportIsIdempotent() throws {
        let row = "2026-10-31T12:30:00Z;Mercado;10,00;expense\n"
        let csv = "date;merchant;amount;kind\n" + row + row
        let first = try CSVImporter.parse(csv)
        let second = try CSVImporter.parse(csv)
        XCTAssertEqual(first.count, 2)
        XCTAssertNotEqual(first[0].id, first[1].id)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TransactionStore(url: directory.appendingPathComponent("test.sqlite"))
        XCTAssertEqual(try store.merge(first), 2)
        XCTAssertEqual(try store.merge(second), 0)
        XCTAssertEqual(try store.all().count, 2)
    }

    func testSignedDecimalPointAndInvalidAmountsAreRejected() {
        for amount in ["-10,00", "+10,00", "10.50", "1,234", "0", "NaN", "92233720368547758,08"] {
            let csv = "date;merchant;amount;kind\n2026-10-31T12:30:00Z;Mercado;\(amount);expense\n"
            XCTAssertThrowsError(try CSVImporter.parse(csv), "Accepted: \(amount)")
        }
    }

    func testDuplicateIdentifiersUnsupportedCurrencyAndMissingColumnsAreRejected() {
        let id = UUID().uuidString
        let row = "\(id);2026-10-31T12:30:00Z;Mercado;10,00;expense;BRL\n"
        XCTAssertThrowsError(try CSVImporter.parse("id;date;merchant;amount;kind;currency\n" + row + row))
        XCTAssertThrowsError(try CSVImporter.parse("date;merchant;amount;kind;currency\n2026-10-31T12:30:00Z;Mercado;10,00;expense;USD\n"))
        XCTAssertThrowsError(try CSVImporter.parse("merchant;amount\nMercado;10,00\n"))
    }

    func testMalformedQuoteAndPartialInvalidFileAreRejectedBeforeStoreMutation() throws {
        XCTAssertThrowsError(try CSVImporter.parse("date;merchant;amount;kind\n2026-10-31T12:30:00Z;\"aberta;10,00;expense"))
        XCTAssertThrowsError(try CSVImporter.parse("date;merchant;amount;kind\n2026-10-31T12:30:00Z;\"Mercado\"x;10,00;expense"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TransactionStore(url: directory.appendingPathComponent("test.sqlite"))
        let csv = "date;merchant;amount;kind\n2026-10-31T12:30:00Z;Mercado;10,00;expense\n2026-10-31T12:30:00Z;Inválido;-2,00;expense\n"
        XCTAssertThrowsError(try store.merge(CSVImporter.parse(csv)))
        XCTAssertTrue(try store.all().isEmpty)
    }

    func testTwentyMegabyteLimitIsCheckedBeforeParsing() {
        XCTAssertThrowsError(try CSVImporter.parse(String(repeating: "x", count: CSVImporter.maximumBytes + 1)))
    }
}

final class ShortcutAmountTests: XCTestCase {
    func testOrdinaryDecimalAmountsAreExact() throws {
        XCTAssertEqual(try ShortcutAmount.minorUnits(0.01), 1)
        XCTAssertEqual(try ShortcutAmount.minorUnits(1.23), 123)
        XCTAssertEqual(try ShortcutAmount.minorUnits(10), 1_000)
        XCTAssertEqual(try ShortcutAmount.minorUnits(1_234.56), 123_456)
    }

    func testInvalidAndSubcentValuesAreRejectedWithoutRounding() {
        for value in [Double(0), -1, .nan, .infinity, -.infinity, 0.001, 1.005, .greatestFiniteMagnitude] {
            XCTAssertThrowsError(try ShortcutAmount.minorUnits(value))
        }
    }

    func testInt64BoundaryIsCheckedBeforeConversion() throws {
        let outsideBoundary = Double(Int64.max) / 100
        XCTAssertThrowsError(try ShortcutAmount.minorUnits(outsideBoundary))
        let insideBoundary = outsideBoundary.nextDown
        let minor = try ShortcutAmount.minorUnits(insideBoundary)
        XCTAssertGreaterThan(minor, 0)
        XCTAssertLessThan(minor, Int64.max)
        XCTAssertThrowsError(try ShortcutAmount.minorUnits(outsideBoundary * 2))
    }
}
