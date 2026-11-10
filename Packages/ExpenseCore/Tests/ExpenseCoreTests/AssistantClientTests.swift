import Foundation
import Testing
@testable import ExpenseCore

@Suite struct AssistantConfigurationTests {
    @Test(arguments: [
        ("https://claude-n-codex.com:8443", "https://claude-n-codex.com:8443/v1/messages"),
        ("https://claude-n-codex.com:8443/", "https://claude-n-codex.com:8443/v1/messages"),
        ("  https://claude-n-codex.com:8443/v1/ ", "https://claude-n-codex.com:8443/v1/messages"),
        ("https://gw.example/claude", "https://gw.example/claude/v1/messages"),
    ])
    func anthropicEndpointIsNormalized(base: String, expected: String) {
        let configuration = AssistantConfiguration(preset: .custom, format: .anthropic, baseURL: base, model: "claude-sonnet-5")
        #expect(configuration.completionsURL?.absoluteString == expected)
        #expect(configuration.isComplete)
    }

    @Test func openAIEndpointKeepsVersionPath() {
        let configuration = AssistantConfiguration(preset: .deepSeek)
        #expect(configuration.completionsURL?.absoluteString == "https://api.munito.ai/inference/v1/chat/completions")
        #expect(configuration.modelsURL?.absoluteString == "https://api.munito.ai/inference/v1/models")
    }

    @Test(arguments: ["http://claude-n-codex.com:8443", "", "claude-n-codex.com", "https://"])
    func onlyHTTPSIsAccepted(base: String) {
        let configuration = AssistantConfiguration(preset: .custom, format: .anthropic, baseURL: base, model: "m")
        #expect(configuration.endpointBase == nil)
        #expect(!configuration.isComplete)
    }

    @Test func serviceRequiresKeyAndAddress() {
        #expect(throws: AssistantError.notConfigured) {
            try AssistantService(configuration: .default, apiKey: "  ", transport: StubTransport([]))
        }
        #expect(throws: AssistantError.invalidBaseURL) {
            try AssistantService(
                configuration: AssistantConfiguration(preset: .custom, format: .anthropic, baseURL: "http://x.y", model: "m"),
                apiKey: "k", transport: StubTransport([])
            )
        }
        #expect(throws: AssistantError.notConfigured) {
            try AssistantService(configuration: AssistantConfiguration(preset: .custom), apiKey: "k", transport: StubTransport([]))
        }
    }

    @Test func roundTripsThroughDefaults() throws {
        let temporary = try TemporaryDefaults()
        #expect(AssistantConfiguration.load(from: temporary.defaults) == .default)
        let custom = AssistantConfiguration(preset: .custom, format: .openAI, baseURL: "https://a.b/v1", model: "x")
        custom.save(to: temporary.defaults)
        #expect(AssistantConfiguration.load(from: temporary.defaults) == custom)
    }
}

@Suite struct AnthropicClientTests {
    private func service(_ transport: StubTransport, sleeper: RecordingSleeper = RecordingSleeper()) throws -> AssistantService {
        try AssistantService(configuration: .default, apiKey: "test-key", transport: transport, sleep: sleeper.sleeper)
    }

    @Test func sendsForcedToolWithBothKeyHeaders() async throws {
        let transport = StubTransport([.json(200, AssistantFixture.anthropicToolReply(AssistantFixture.twoExpenses))])
        let result = try await service(transport).parse(AssistantInput(text: "выпил пива 7.50, сходил в компы 12 рублей"), context: AssistantFixture.context)

        #expect(result.items.map(\.amountMinor) == [750, 1200])
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://claude-n-codex.com:8443/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try transport.body(0)
        #expect(body["model"] as? String == "claude-sonnet-5")
        #expect((body["tool_choice"] as? [String: String]) == ["type": "tool", "name": "record_expenses"])
        #expect(body["thinking"] == nil)
        #expect(body["output_config"] == nil)
        let tool = try #require((body["tools"] as? [[String: Any]])?.first)
        let schema = try #require(tool["input_schema"] as? [String: Any])
        let item = try #require(((schema["properties"] as? [String: Any])?["expenses"] as? [String: Any])?["items"] as? [String: Any])
        let category = try #require((item["properties"] as? [String: Any])?["category"] as? [String: Any])
        let variants = try #require(category["anyOf"] as? [[String: Any]])
        #expect(variants.first?["enum"] as? [String] == ["c01", "c02", "c03", "c04"])
    }

    @Test func imagesGoBeforeTextWithLabels() async throws {
        let transport = StubTransport([.json(200, AssistantFixture.anthropicToolReply(AssistantFixture.twoExpenses))])
        let photo = try AssistantFixture.jpeg(width: 600, height: 400)
        _ = try await service(transport).parse(AssistantInput(text: "вчерашний чек", images: [photo]), context: AssistantFixture.context)

        let messages = try #require(try transport.body(0)["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["text", "image", "text"])
        #expect(content[0]["text"] as? String == "Фото:")
        let source = try #require(content[1]["source"] as? [String: String])
        #expect(source["type"] == "base64")
        #expect(source["media_type"] == "image/jpeg")
        #expect(content[2]["text"] as? String == "Разбери траты на фото. Комментарий пользователя: вчерашний чек")
        #expect(transport.requests.first?.timeoutInterval == AssistantService.photoTimeout)
    }

    @Test func fallsBackToAutoToolChoiceWhenForcedIsRejected() async throws {
        let transport = StubTransport([
            .json(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"tool_choice: type \"tool\" and \"any\" are not supported for this model."}}"#),
            .json(200, AssistantFixture.anthropicToolReply(AssistantFixture.twoExpenses)),
        ])
        let result = try await service(transport).parse(AssistantInput(text: "пиво 7.50"), context: AssistantFixture.context)

        #expect(result.items.count == 2)
        #expect((try transport.body(1)["tool_choice"] as? [String: String]) == ["type": "auto"])
        #expect((try transport.body(1)["system"] as? String)?.hasSuffix("Ответь вызовом инструмента record_expenses.") == true)
    }

    @Test func otherBadRequestIsNotRetried() async throws {
        let transport = StubTransport([.json(400, #"{"error":{"message":"messages: too long"}}"#)])
        await #expect(throws: AssistantError.badRequest) {
            try await service(transport).parse(AssistantInput(text: "x"), context: AssistantFixture.context)
        }
        #expect(transport.requestCount == 1)
    }

    @Test func readsJSONFromTextWhenToolIsNotCalled() throws {
        let reply = #"{"content":[{"type":"text","text":"Вот:\n```json\n{\"expenses\":[],\"receipt\":null,\"unparsed\":[\"зарплата\"]}\n```"}],"stop_reason":"end_turn"}"#
        let json = try AnthropicMessagesClient.parse(Data(reply.utf8), toolName: "record_expenses")
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["unparsed"] as? [String] == ["зарплата"])
    }

    @Test(arguments: [("refusal", AssistantError.refused), ("max_tokens", AssistantError.truncated)])
    func stopReasonsBecomeErrors(stopReason: String, expected: AssistantError) {
        let reply = AssistantFixture.anthropicToolReply("{}", stopReason: stopReason)
        #expect(throws: expected) { try AnthropicMessagesClient.parse(Data(reply.utf8), toolName: "record_expenses") }
    }

    @Test func retriesRateLimitOnceHonoringRetryAfter() async throws {
        let sleeper = RecordingSleeper()
        let transport = StubTransport([
            .json(429, "{}", headers: ["retry-after": "30"]),
            .json(200, AssistantFixture.anthropicToolReply(AssistantFixture.twoExpenses)),
        ])
        _ = try await service(transport, sleeper: sleeper).parse(AssistantInput(text: "x"), context: AssistantFixture.context)
        #expect(sleeper.delays == [RetryDelay.maxDelay])
        #expect(transport.requestCount == 2)
    }

    @Test func overloadedTwiceIsServerUnavailable() async throws {
        let sleeper = RecordingSleeper()
        let transport = StubTransport([.json(529, "{}"), .json(529, "{}")])
        await #expect(throws: AssistantError.serverUnavailable) {
            try await service(transport, sleeper: sleeper).parse(AssistantInput(text: "x"), context: AssistantFixture.context)
        }
        #expect(sleeper.delays == [RetryDelay.fallbackDelay])
    }

    @Test(arguments: [
        (401, AssistantError.unauthorized), (403, .unauthorized), (402, .paymentRequired),
        (404, .modelNotFound), (413, .tooLarge), (422, .badRequest),
    ])
    func statusesMapWithoutRetry(status: Int, expected: AssistantError) async throws {
        let transport = StubTransport([.json(status, "{}")])
        await #expect(throws: expected) {
            try await service(transport).parse(AssistantInput(text: "x"), context: AssistantFixture.context)
        }
        #expect(transport.requestCount == 1)
    }

    @Test(arguments: [(URLError.Code.notConnectedToInternet, AssistantError.offline), (.timedOut, .timeout)])
    func networkFailures(code: URLError.Code, expected: AssistantError) async throws {
        let transport = StubTransport([.failure(code)])
        await #expect(throws: expected) {
            try await service(transport).parse(AssistantInput(text: "x"), context: AssistantFixture.context)
        }
    }

    @Test func listsModels() async throws {
        let transport = StubTransport([.json(200, #"{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"}]}"#)])
        #expect(try await service(transport).availableModels() == ["claude-sonnet-5", "claude-opus-5"])
        #expect(transport.requests.first?.url?.absoluteString == "https://claude-n-codex.com:8443/v1/models")
        #expect(transport.requests.first?.httpMethod == "GET")
    }

    @Test func connectionCheckNeedsSchemaAnswer() async throws {
        let ok = StubTransport([.json(200, AssistantFixture.anthropicToolReply(#"{"ok":true}"#, tool: "connection_check"))])
        _ = try await service(ok).checkConnection()
        let wrong = StubTransport([.json(200, AssistantFixture.anthropicToolReply(#"{"status":"fine"}"#, tool: "connection_check"))])
        await #expect(throws: AssistantError.unreadableResponse) { try await service(wrong).checkConnection() }
    }
}

@Suite struct OpenAIClientTests {
    private func service(_ transport: StubTransport) throws -> AssistantService {
        try AssistantService(configuration: AssistantConfiguration(preset: .deepSeek), apiKey: "munito-key", transport: transport, sleep: RecordingSleeper().sleeper)
    }

    @Test func sendsStrictSchemaAndBearerKey() async throws {
        let transport = StubTransport([.json(200, AssistantFixture.openAIReply(AssistantFixture.twoExpenses))])
        let photo = try AssistantFixture.jpeg(width: 300, height: 300)
        let result = try await service(transport).parse(AssistantInput(text: "", images: [photo]), context: AssistantFixture.context)

        #expect(result.items.count == 2)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.munito.ai/inference/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer munito-key")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
        let body = try transport.body(0)
        #expect(body["model"] as? String == "deepseek-ai/deepseek-v4.1-flash-1017")
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect((format["json_schema"] as? [String: Any])?["strict"] as? Bool == true)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
        let content = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["text", "image_url", "text"])
        let url = try #require((content[1]["image_url"] as? [String: String])?["url"])
        #expect(url.hasPrefix("data:image/jpeg;base64,"))
    }

    @Test func fallsBackToJSONObjectWhenSchemaIsRejected() async throws {
        let transport = StubTransport([
            .json(400, #"{"error":{"message":"response_format json_schema is not supported"}}"#),
            .json(200, AssistantFixture.openAIReply("```json\n" + AssistantFixture.twoExpenses + "\n```")),
        ])
        let result = try await service(transport).parse(AssistantInput(text: "x"), context: AssistantFixture.context)
        #expect(result.items.count == 2)
        #expect((try transport.body(1)["response_format"] as? [String: String]) == ["type": "json_object"])
    }

    @Test(arguments: [("length", AssistantError.truncated), ("content_filter", .refused)])
    func finishReasonsBecomeErrors(reason: String, expected: AssistantError) {
        let reply = AssistantFixture.openAIReply("{}", finishReason: reason)
        #expect(throws: expected) { try OpenAIChatClient.parse(Data(reply.utf8)) }
    }

    @Test func emptyContentIsUnreadable() {
        #expect(throws: AssistantError.unreadableResponse) {
            try OpenAIChatClient.parse(Data(#"{"choices":[{"message":{"content":null},"finish_reason":"stop"}]}"#.utf8))
        }
    }
}
