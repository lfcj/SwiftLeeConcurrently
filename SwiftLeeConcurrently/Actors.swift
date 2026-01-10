@globalActor
actor AccountInfo: GlobalActor {
    static let shared = AccountInfo()
}

extension Actor {
    @discardableResult
    func performInIsolation<T: Sendable>(_ closure: @escaping (isolated Self) throws -> T) async rethrows -> T {
        try closure(self)
    }
}
