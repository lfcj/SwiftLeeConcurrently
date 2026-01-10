public class PersonViewModel {
    var personName: String! = "Default"
}

public class BankAccount {
    var saldo: Int = 0
}

public struct Person: Sendable {
    let name: String
    let account: BankAccount

    var saldo: Int { account.saldo }
}

public struct SimplePerson {
    var name: String
}

struct SendableChecker: Sendable {
    let person = SimplePerson(name: "Antoine")
    
    func check() {
        Task {
            /// A compiler error will show up here if `person` isn't `Sendable`.
            print(person.name)
        }
    }
}

actor ActorBankAccount {
    let firstName: String = ""
    let lastName: String = ""
    nonisolated var fullName: String { "\(firstName) \(lastName)" }
    func payMortgage() {}
    func payUtilities() {}
    func payTaxes() {}
    func payMonthlyBills(_ perform: @escaping (isolated ActorBankAccount) -> Void) {
        perform(self)
    }
}

class RichPerson {
    let bankAccount: ActorBankAccount = ActorBankAccount()
    func payBills() async {
        print("paying bills for \(bankAccount.fullName)")
        await bankAccount.payMonthlyBills { account in
            account.payMortgage()
            account.payUtilities()
            account.payTaxes()
        }
        await bankAccount.performInIsolation { account in
            account.payMortgage()
            account.payUtilities()
            account.payTaxes()
        }
    }
}
