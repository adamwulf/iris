import Foundation

/// Builds the URL of Google's sign-in page.
enum GoogleURL {
    /// `base` with `query` in this order. Each name and value is
    /// percent-encoded except letters, digits, and `-._~`. `URLComponents`
    /// alone leaves `+` as it is, but Google reads a `+` in a query as a space,
    /// which would break a login hint such as `me+mail@gmail.com`; here it
    /// becomes `%2B`. Nil when `base` is not a URL.
    static func build(_ base: String, query: [(String, String)]) -> URL? {
        guard var components = URLComponents(string: base) else {
            return nil
        }
        components.percentEncodedQueryItems = query.map { name, value in
            URLQueryItem(name: FormEncoder.escape(name), value: FormEncoder.escape(value))
        }
        return components.url
    }
}
