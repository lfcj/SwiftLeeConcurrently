import Foundation
import Synchronization

class MutexBankAccount {
    private let balance = Mutex<Int>(0)

    enum Error: Swift.Error {
        case reachedZero
    }
    var currentBalance: Int {
        balance.withLock { currentBalance in
            return currentBalance
        }
    }

    func deposit(_ amount: Int) {
        balance.withLock { currentBalance in
            currentBalance += amount
        }
    }

    func withdraw(_ amount: Int) -> Bool {
        return balance.withLock { currentBalance in
            guard currentBalance >= amount else { return false }
            currentBalance -= amount
            return true
        }
    }

    func throwingWithdraw(_ amount: Int) throws {
        try balance.withLock { currentBalance in
            guard currentBalance >= amount else { throw Error.reachedZero }
            currentBalance -= amount
        }
    }
}
