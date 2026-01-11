extension Collection where Element: Sendable {
    func sequentialMap<Result: Sendable>(
        transform: (Element) async -> Result
    ) async -> [Result] {
        var results: [Result] = []
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}

actor TestingIsolationMacro {
    func test() {
        Task { @MainActor in
            let names = ["Antoine", "Maaike", "Sep", "Jip"]
            let lowercaseNames = await names.sequentialMap { name in
                await lowercaseWithSleep(input: name)
            }
            print(lowercaseNames)
        }
    }

    func lowercaseWithSleep(input: String) async -> String {
        try? await Task.sleep(for: .seconds(2))
        return input.lowercased()
    }
}
