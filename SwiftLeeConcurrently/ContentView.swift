//

import SwiftUI

struct ContentView: View {
    @State var message = "Hello, world!"
    var body: some View {
        VStack {
            Text(message)
        }
        .task {
            let viewModel = PersonViewModel()
            Task {
                //viewModel.personName = nil // Unlock to cause a crash
            }
            Task {
                message = viewModel.personName
            }
        }
    }
}

#Preview {
    ContentView()
}
