import AppKit
import Foundation
import XCTest
@testable import PastportKit

final class ScreenshotReaderTests: XCTestCase {
    private final class CallbackState: @unchecked Sendable {
        var calls = 0
    }

    private enum SyntheticRecognitionError: Error {
        case invalidImage
    }

    func testReaderReturnsOnlySanitizedEmailEvidence() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["Contact alice@example.test about the reservation"]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["Contact [EMAIL] about the reservation"])
        XCTAssertEqual(evidence.redactionCount, 1)
        XCTAssertFalse(evidence.text.contains("alice@example.test"))
    }

    func testChatAndBankingScreenshotsAreExcludedUntilExplicitOptIn() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["WhatsApp", "Family bank account balance", "UPI transaction 4242 4242 4242 4242"]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-banking-chat.png")
        )

        XCTAssertEqual(evidence.kind, .banking)
        XCTAssertNil(evidence.narrationText())
        XCTAssertNotNil(evidence.narrationText(allowSensitive: true))
    }

    func testNarrationCallbackIsGatedBeforeItRuns() async throws {
        let sensitive = ScreenshotReader(recognize: { _ in ["Family chat"] })
        let unknown = ScreenshotReader(recognize: {
            _ in ["Can you book the hotel for our flight? Check the map before dinner."]
        })
        let state = CallbackState()
        let callback: @Sendable (String) async throws -> String = { text in
            state.calls += 1
            return "model saw: \(text)"
        }

        let sensitiveResult = try await sensitive.narrate(
            imageAt: URL(fileURLWithPath: "/sensitive.png"), using: callback
        )
        let unknownResult = try await unknown.narrate(
            imageAt: URL(fileURLWithPath: "/unknown.png"), using: callback
        )
        XCTAssertNil(sensitiveResult)
        XCTAssertNil(unknownResult)
        XCTAssertEqual(state.calls, 0)

        let optInResult = try await unknown.narrate(
            imageAt: URL(fileURLWithPath: "/unknown.png"),
            allowSensitive: true,
            using: callback
        )
        XCTAssertEqual(state.calls, 1)
        XCTAssertEqual(
            optInResult,
            "model saw: Can you book the hotel for our flight? Check the map before dinner."
        )
    }

    func testExplicitOptInPassesOnlyScrubbedSensitiveText() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["Bank balance 4242 4242 4242 4242, alice@example.test"]
        })

        let result = try await reader.narrate(
            imageAt: URL(fileURLWithPath: "/bank.png"),
            allowSensitive: true,
            using: { text in text }
        )

        XCTAssertEqual(result, "Bank balance [CARD], [EMAIL]")
    }

    func testReceiptScreenshotsAreOptInButOrdinaryScreenshotsCanNarrate() async throws {
        let receipt = ScreenshotReader(recognize: { _ in ["Tax invoice", "Order total 1200"] })
        let ordinary = ScreenshotReader(recognize: { _ in ["Kyoto itinerary"] })

        let receiptEvidence = try await receipt.read(
            imageAt: URL(fileURLWithPath: "/synthetic-receipt.png")
        )
        let ordinaryEvidence = try await ordinary.read(
            imageAt: URL(fileURLWithPath: "/synthetic-travel.png")
        )

        XCTAssertEqual(receiptEvidence.kind, .receipt)
        XCTAssertNil(receiptEvidence.narrationText())
        XCTAssertEqual(ordinaryEvidence.kind, .unknown)
        XCTAssertNil(ordinaryEvidence.narrationText())
        XCTAssertEqual(
            ordinaryEvidence.narrationText(allowSensitive: true), "Kyoto itinerary"
        )
    }

    func testReaderRedactsContextualVerificationCode() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["Your verification code is 482931"]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["Your [OTP]"])
        XCTAssertEqual(evidence.redactionCount, 1)
        XCTAssertFalse(evidence.text.contains("482931"))
    }

    func testReaderRedactsCommonOTPFormatting() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            [
                "OTP is: 482931",
                "OTP – 482931",
                "one-time password (OTP) is 482931",
                "OTP: 1 2 3 4 5 6 7 8",
            ]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["[OTP]", "[OTP]", "[OTP]", "[OTP]"])
        XCTAssertEqual(evidence.redactionCount, 4)
    }

    func testReaderRedactsCardShapedDigits() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["Card number 4242 4242 4242 4242"]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["Card number [CARD]"])
        XCTAssertEqual(evidence.redactionCount, 1)
        XCTAssertFalse(evidence.text.contains("4242"))
    }

    func testReaderRedactsSeveralSensitiveSpansOnOneLine() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["Email alice@example.test, OTP: 482931, card 4242-4242-4242-4242"]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["Email [EMAIL], [OTP], card [CARD]"])
        XCTAssertEqual(evidence.redactionCount, 3)
    }

    func testReaderRedactsSensitiveSpansSplitAcrossOCRLines() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            [
                "Contact alice@",
                "example.test",
                "OTP",
                "482931",
                "Card 4242 4242",
                "4242 4242",
            ]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, [
            "Contact [EMAIL]",
            "[OTP]",
            "Card [CARD]",
        ])
        XCTAssertEqual(evidence.redactionCount, 3)
    }

    func testReaderRedactsUnicodeEmailAndOCRSeparators() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            [
                "Contact álîçé@例え.テスト",
                "Card 4242\u{00A0}\u{00A0}4242\t4242–4242",
            ]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["Contact [EMAIL]", "Card [CARD]"])
        XCTAssertEqual(evidence.redactionCount, 2)
    }

    func testReaderPreservesOrdinaryTravelNumbers() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            ["Arrival Jun 16, total 4829, booking 12345678"]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, ["Arrival Jun 16, total 4829, booking 12345678"])
        XCTAssertEqual(evidence.redactionCount, 0)
    }

    func testReaderUsesCardLengthBoundaries() async throws {
        let reader = ScreenshotReader(recognize: { _ in
            [
                "short 1234 5678 9012",
                "minimum 1234 5678 9012 3",
                "maximum 1234 5678 9012 3456 789",
            ]
        })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, [
            "short 1234 5678 9012",
            "minimum [CARD]",
            "maximum [CARD]",
        ])
        XCTAssertEqual(evidence.redactionCount, 2)
    }

    func testReaderReturnsEmptyEvidenceWhenVisionFindsNoText() async throws {
        let reader = ScreenshotReader(recognize: { _ in [] })

        let evidence = try await reader.read(
            imageAt: URL(fileURLWithPath: "/synthetic-screenshot.png")
        )

        XCTAssertEqual(evidence.lines, [])
        XCTAssertEqual(evidence.text, "")
        XCTAssertEqual(evidence.redactionCount, 0)
    }

    func testProductionReaderUsesVisionBeforeScrubbing() async throws {
        let imageURL = try syntheticPNG(containing: "WhatsApp FAMILY BANK\nAccount balance\nOTP: 482931\nCard: 4242 4242 4242 4242\nEmail: alice@example.test")
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let evidence = try await ScreenshotReader().read(imageAt: imageURL)

        XCTAssertTrue(evidence.lines.contains { $0.localizedCaseInsensitiveContains("WhatsApp") },
                      "Vision must recognize meaningful synthetic text: \(evidence.lines)")
        XCTAssertEqual(evidence.kind, .banking)
        XCTAssertTrue(evidence.lines.contains { $0.contains("[EMAIL]") },
                      "sanitized synthetic OCR: \(evidence.lines)")
        XCTAssertTrue(evidence.lines.contains { $0.contains("[OTP]") },
                      "sanitized synthetic OCR: \(evidence.lines)")
        XCTAssertTrue(evidence.lines.contains { $0.contains("[CARD]") },
                      "sanitized synthetic OCR: \(evidence.lines)")
        XCTAssertEqual(evidence.redactionCount, 3)
        XCTAssertFalse(evidence.text.contains("alice@example.test"))
        XCTAssertFalse(evidence.text.contains("482931"))
        XCTAssertFalse(evidence.text.contains("4242"))

        let callbackState = CallbackState()
        let narration = try await ScreenshotReader().narrate(imageAt: imageURL) { _ in
            callbackState.calls += 1
            return "unexpected narration"
        }
        XCTAssertNil(narration)
        XCTAssertEqual(callbackState.calls, 0)
    }

    func testProductionReaderRejectsMissingImage() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        do {
            _ = try await ScreenshotReader().read(imageAt: url)
            XCTFail("a missing image must not produce evidence")
        } catch {
            // Actual Vision failed closed without producing an evidence value.
        }
    }

    func testReaderDoesNotReturnPartialEvidenceAfterRecognitionFailure() async {
        let reader = ScreenshotReader(recognize: { _ in
            throw SyntheticRecognitionError.invalidImage
        })
        do {
            _ = try await reader.read(
                imageAt: URL(fileURLWithPath: "/invalid-synthetic-image.png")
            )
            XCTFail("invalid image data must not produce partial evidence")
        } catch SyntheticRecognitionError.invalidImage {
            // The recognizer error escaped and no evidence value was produced.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func syntheticPNG(containing text: String) throws -> URL {
        let size = NSSize(width: 1_800, height: 500)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 42, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            (line as NSString).draw(
                at: NSPoint(x: 40, y: size.height - CGFloat(index + 1) * 78),
                withAttributes: attributes
            )
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ScreenshotReaderTests", code: 1)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try png.write(to: url, options: .atomic)
        return url
    }
}
