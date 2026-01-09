class Article {
    var title: String
    init(title: String) {
        self.title = title
    }
}

struct ArticleSendableChecker: Sendable {
    func check() {
        let person = SimplePerson(name: "Antoine")
        Task {
            print(person.name)
        }
        //print(person.name) -> this causes an error as the line inside `Task` already transfers the non-sendable object into the tasks' isolation task.
    }

    @MainActor
    func check2(person: sending SimplePerson) {
        Task(priority: .userInitiated) {
            print(person.name)
        }
        person.name = "Hi"
    }

    @MainActor
    func makePerson(name: String) -> sending SimplePerson {
        SimplePerson(name: name)
    }

    func makePersonAndPrintIt() async {
        let person = await makePerson(name: "some name")
        print(person.name)
    }
}

actor ArticleTitleLogger {
    func log(article: Article) {
        print(article.title)
    }
}
