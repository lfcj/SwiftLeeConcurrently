//import Foundation
//import SwiftUI
//
//struct TaskGroups {
//    func notCancellingOtherTasks() async {
//        await withThrowingTaskGroup(of: Void.self) { group in
//            (0..<5).forEach { index in
//                group.addTask {
//                    if index == 3 {
//                        throw NSError(domain: "test", code: 0)
//                    } else {
//                        print("index: \(index)")
//                    }
//                }
//            }
//        }
//    }
//
//    func discardingAndNotCancellingOtherTasks() async throws -> Int {
//        return try await withThrowingDiscardingTaskGroup(returning: Int.self) { group in
//           var addedTasks = 0
//           (0..<5).forEach { index in
//               if index % 2 == 0 {
//                   group.addTask {
//                       print("index: \(index)")
//                   }
//                   addedTasks += 1
//               } else {
//                   group.addTask {
//                       throw NSError(domain: "test", code: 0)
//                   }
//               }
//           }
//           return addedTasks
//         }
//    }
//}
//
//struct SomeView: View {
//    @State var addedTasks = 0
//
//    var body: some View {
//        Text("Hello world: \(addedTasks)")
//            .task {
//                Task.detached {
//                    print("Default task priority: \(Task.currentPriority)")
//                }
//            }
//    }
//
//    func runThrowingTask() async {
//        do {
//            addedTasks = try await TaskGroups().discardingAndNotCancellingOtherTasks()
//        } catch {
//            print("Rethrown error: \(error)")
//        }
//    }
//
//    func runNonThrowingTask() async {
//        await TaskGroups().notCancellingOtherTasks()
//    }
//}
//extension PersonViewModel: Sendable {}
//#Preview {
//    SomeView()
//}
