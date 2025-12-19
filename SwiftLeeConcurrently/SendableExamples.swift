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
