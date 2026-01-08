import Foundation

struct PlannedTransaction {
    let dueDate: Date
    let lastDate: Date
    let amount: Int
}

actor BankAccount2 {
    private(set) var money: Int = 0
    private let plannedTransactions: [PlannedTransaction] = []

    func transferMoney(_ amount: Int) {
        money -= amount
    }

    nonisolated func performMonthlyTransaction(_ canHappen: @escaping @Sendable (PlannedTransaction) -> Bool) async {
        plannedTransactions.forEach { plannedTransaction in
            Task {
                if canHappen(plannedTransaction) {
                    await transferMoney(plannedTransaction.amount)
                }
            }
        }
    }
}

actor Country {
    let taxes: Int = 1000

    let bankAccounts = [BankAccount2]()

    func performTransactions() async {
        await withTaskGroup(of: Void.self) { [taxes] group in
            bankAccounts.forEach { account in
                group.addTask {
                    await account.transferMoney(taxes)
                }
            }
            
        }
    }
    
}
