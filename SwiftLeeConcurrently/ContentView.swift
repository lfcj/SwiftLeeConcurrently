//

import SwiftUI

struct ContentView: View {
    @State var message = "Hello, world!"
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(message)
        }
        .padding()
        .task {
            let result = await NetworkOperatorPerformer().invokeUponNetworkAccess(within: .seconds(3), { "hi" })
            message = (try? result.get()) ?? "Error"
        }
    }
}

#Preview {
    ContentView()
}
