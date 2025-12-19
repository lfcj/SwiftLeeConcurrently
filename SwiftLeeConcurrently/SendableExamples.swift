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


