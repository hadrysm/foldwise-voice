import AVFoundation
import XCTest
@testable import FoldWiseVoiceKit

/// The chunk handed to a streaming manager must already be in the recorder's
/// format, so the engine's own converter has nothing left to resample.
final class StreamingAudioChunkTests: XCTestCase {
    func testChunkKeepsTheCaptureSampleRate() throws {
        let buffer = try StreamingAudioChunk.buffer(for: [0.1, 0.2])

        XCTAssertEqual(buffer.format.sampleRate, AudioRecorder.sampleRate)
    }

    func testChunkIsMono() throws {
        let buffer = try StreamingAudioChunk.buffer(for: [0.1, 0.2])

        XCTAssertEqual(buffer.format.channelCount, 1)
    }

    func testChunkLengthMatchesTheSampleCount() throws {
        let buffer = try StreamingAudioChunk.buffer(for: [0.1, 0.2, 0.3])

        XCTAssertEqual(buffer.frameLength, 3)
    }

    func testChunkCarriesTheSamplesVerbatim() throws {
        let samples: [Float] = [0.1, -0.25, 0.5]
        let buffer = try StreamingAudioChunk.buffer(for: samples)

        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: channel, count: samples.count)), samples)
    }

    func testEmptyChunkIsRefusedWithAReadableReason() {
        XCTAssertThrowsError(try StreamingAudioChunk.buffer(for: [])) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Couldn't prepare the captured audio for transcription."
            )
        }
    }
}
