// Tracer bullet for the Pipeline seams (ADR-0002): one full dictation
// session driven entirely through the public interface with fakes, asserting
// the emitted progress-state sequence.

import XCTest
@testable import FoldWiseVoiceKit

final class PipelineSessionTests: XCTestCase {
    func testFullSessionEmitsListeningTranscribingInserted() async {
        let transcriber = FakeTranscriber()
        transcriber.result = .success("hello world")
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            transcriber: transcriber,
            polish: { text, _ in text },
            insert: { _ in true }
        )
        let collector = StateCollector()
        pipeline.onState = { collector.append($0) }

        pipeline.startRecording()
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()

        XCTAssertEqual(
            collector.states,
            [.listening(mode: "Voice to Text"), .transcribing, .inserted]
        )
    }
}
