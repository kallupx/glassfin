import TVServices

@objc(GlassfinTopShelfProvider)
final class GlassfinTopShelfProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        completionHandler(nil)
    }
}
