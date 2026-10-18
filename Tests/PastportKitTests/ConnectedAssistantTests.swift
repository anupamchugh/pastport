import Foundation
import FoundationLabCore
import FoundationModels
import FoundationModelsKit
import Testing
@testable import PastportKit

@MainActor
private final class GenerationBox {
    var value = UUID()
}

private actor CallRecorder {
    var count = 0
    func record() { count += 1 }
}

@Generable
private struct FakeToolArguments: RuntimeCompatibleGenerable {
    @Guide(description: "A harmless test value")
    var value: String

    init(value: String = "test") {
        self.value = value
    }
}

private struct FakeConnectedTool: Tool {
    let recorder: CallRecorder
    let name = "fakeConnectedTool"
    let description = "A test-only tool"

    func call(arguments: FakeToolArguments) async throws -> GeneratedContent {
        await recorder.record()
        return GeneratedContent(properties: ["status": "called"])
    }
}

@Suite("Connected assistant policy")
struct ConnectedAssistantTests {
    @Test("tool selection is capped at three")
    func toolSelectionCap() {
        let selected: [FoundationLabBuiltInTool] = [.weather, .web, .calendar]
        #expect(ConnectedAssistantPolicy.canSelect(.weather, alongside: selected))
        #expect(!ConnectedAssistantPolicy.canSelect(.contacts, alongside: selected))
    }

    @Test("contact and music adapters reject mutating actions")
    func mutationActionsAreDenied() {
        #expect(ConnectedAssistantPolicy.permitsContactAction("search"))
        #expect(ConnectedAssistantPolicy.permitsContactAction("read"))
        #expect(!ConnectedAssistantPolicy.permitsContactAction("create"))
        #expect(ConnectedAssistantPolicy.permitsMusicAction("search"))
        #expect(ConnectedAssistantPolicy.permitsMusicAction("nowPlaying"))
        #expect(!ConnectedAssistantPolicy.permitsMusicAction("play"))
        #expect(!ConnectedAssistantPolicy.permitsMusicAction("pause"))
    }

    @Test("pending approval can be cancelled without invoking a service")
    func pendingApprovalCancellation() async throws {
        let (events, continuation) = AsyncStream<UUID>.makeStream()
        let coordinator = ConnectedToolApprovalCoordinator(onRequest: { continuation.yield($0.id) })
        var iterator = events.makeAsyncIterator()
        let request = ConnectedToolApprovalRequest(
            generation: UUID(), toolName: "getWeather", arguments: "{\"city\":\"Paris\"}",
            destination: "Weather", service: "Open-Meteo + MapKit"
        )
        let waiting = Task { try await coordinator.request(request) }
        _ = await iterator.next()
        await coordinator.cancel(request.id)
        #expect(try await waiting.value == false)
    }

    @Test("cancelling all approvals resolves every stale continuation")
    func staleGenerationCancellation() async throws {
        let (events, continuation) = AsyncStream<UUID>.makeStream()
        let coordinator = ConnectedToolApprovalCoordinator(onRequest: { continuation.yield($0.id) })
        var iterator = events.makeAsyncIterator()
        let requests = (0..<2).map { _ in
            ConnectedToolApprovalRequest(
                generation: UUID(), toolName: "readContacts", arguments: "{}",
                destination: "Contacts", service: "Contacts"
            )
        }
        let waiting = requests.map { request in
            Task { try await coordinator.request(request) }
        }
        for _ in requests { _ = await iterator.next() }
        await coordinator.cancelAll()
        for task in waiting {
            #expect(try await task.value == false)
        }
    }

    @Test("health availability is a runtime policy, never a fabricated capability")
    func healthPolicy() {
        #expect(ConnectedAssistantPolicy.isAvailable(.health) == ConnectedAssistantPolicy.healthIsAvailable)
    }

    @MainActor
    @Test("clear invalidates the generation and removes pending state")
    func clearInvalidatesGeneration() {
        let assistant = ConnectedAssistant()
        let oldGeneration = assistant.generation
        assistant.clear()
        #expect(assistant.generation != oldGeneration)
        #expect(assistant.pendingApproval == nil)
        #expect(assistant.toolReceipts.isEmpty)
    }

    @MainActor
    @Test("changing tools cancels busy state and starts a new generation")
    func toolChangeInvalidatesInFlightState() {
        let assistant = ConnectedAssistant()
        assistant.toggleTool(.weather)
        let oldGeneration = assistant.generation
        assistant.toggleTool(.web)
        #expect(assistant.generation != oldGeneration)
        #expect(!assistant.isLoading)
    }

    @MainActor
    @Test("generation invalidation after approval prevents the underlying call")
    func staleGenerationDoesNotInvokeService() async throws {
        let generation = GenerationBox()
        let recorder = CallRecorder()
        let coordinator = ConnectedToolApprovalCoordinator()
        let (events, continuation) = AsyncStream<UUID>.makeStream()
        var iterator = events.makeAsyncIterator()
        await coordinator.setRequestHandler { request in
            continuation.yield(request.id)
        }
        let tool = ApprovedTool(
            base: FakeConnectedTool(recorder: recorder),
            approval: coordinator,
            generationProvider: { generation.value },
            destination: "Test",
            service: "Injected fake",
            receipt: { _ in }
        )
        let pending = Task {
            try await tool.call(arguments: FakeToolArguments())
        }
        let id = try #require(await iterator.next())
        generation.value = UUID()
        await coordinator.resolve(id, approved: true)
        do {
            _ = try await pending.value
        } catch {
            #expect(error as? ConnectedToolApprovalError == .staleGeneration)
        }
        #expect(await recorder.count == 0)
    }
}
