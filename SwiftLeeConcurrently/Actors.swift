@globalActor
actor AccountInfo: GlobalActor {
    static let shared = AccountInfo()
}

extension Actor {
    @discardableResult
    func performInIsolation<T: Sendable>(_ closure: @Sendable (isolated Self) throws -> T) async rethrows -> T {
        try closure(self)
    }
}

@MainActor
final class EquatableBankAccount {
    let holder: String
    var balance: Double

    init(holder: String, balance: Double) {
        self.holder = holder
        self.balance = balance
    }
}

extension EquatableBankAccount: @MainActor Equatable {
    static func == (lhs: EquatableBankAccount, rhs: EquatableBankAccount) -> Bool {
        lhs.holder == rhs.holder && lhs.balance == rhs.balance
    }
}
