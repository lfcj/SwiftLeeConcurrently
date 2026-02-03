//import Foundation
//
//class ArticleTitlesCache: Sendable {
//    private let cacheMutatingLock = DispatchQueue(label: "cache.lock.queue")
//
//    /// A private mutable member which is only accessed inside this cache via the serial lock queue.
//    private var articleTitles: Set<String> = []
//
//    func addArticleTitle(_ title: String) {
//        cacheMutatingLock.sync {
//            _ = articleTitles.insert(title)
//        }
//    }
//
//    func cachedArticleTitles() -> Set<String> {
//        return cacheMutatingLock.sync {
//            return articleTitles
//        }
//    }
//}
