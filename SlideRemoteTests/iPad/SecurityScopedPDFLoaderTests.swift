//
//  SecurityScopedPDFLoaderTests.swift
//  SlideRemoteTests
//

import Testing
import Foundation
import PDFKit
@testable import SlideRemote

struct SecurityScopedPDFLoaderTests {
    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }

    private func validPDFData() -> Data {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        return document.dataRepresentation() ?? Data()
    }

    /// Devolve o erro lançado ou nil se carregou.
    private func loadError(_ loader: SecurityScopedPDFLoader, _ url: URL) -> PDFLoadError? {
        do {
            _ = try loader.load(from: url)
            return nil
        } catch {
            return error
        }
    }

    @Test func loadsAValidPDF() throws {
        let url = try temporaryFile(validPDFData())
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try SecurityScopedPDFLoader().load(from: url)
        #expect(document.pageCount == 1)
    }

    @Test func rejectsFilesAboveTheSizeLimit() throws {
        let url = try temporaryFile(Data(count: 1_001))
        defer { try? FileManager.default.removeItem(at: url) }

        let error = loadError(SecurityScopedPDFLoader(maxFileSize: 1_000), url)
        guard case .fileTooLarge = error else {
            Issue.record("esperava .fileTooLarge, veio \(String(describing: error))")
            return
        }
    }

    @Test func fileExactlyAtTheLimitIsStillRead() throws {
        let url = try temporaryFile(Data(count: 1_000))
        defer { try? FileManager.default.removeItem(at: url) }

        let error = loadError(SecurityScopedPDFLoader(maxFileSize: 1_000), url)
        guard case .invalidDocument = error else {
            Issue.record("esperava .invalidDocument, veio \(String(describing: error))")
            return
        }
    }

    @Test func rejectsContentThatIsNotAPDF() throws {
        let url = try temporaryFile(Data("isto não é um pdf".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        guard case .invalidDocument = loadError(SecurityScopedPDFLoader(), url) else {
            Issue.record("esperava .invalidDocument")
            return
        }
    }

    @Test func reportsAMissingFileAsReadFailure() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        guard case .readFailed = loadError(SecurityScopedPDFLoader(), url) else {
            Issue.record("esperava .readFailed")
            return
        }
    }

    @Test func tooLargeErrorHasAUserFacingMessage() {
        #expect(PDFLoadError.fileTooLarge.errorDescription == "Esse PDF é grande demais para abrir.")
    }
}
