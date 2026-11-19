import SwiftUI
import UIKit

/// Puts an icon on the home screen through Safari. iOS lets no app place one there itself, but
/// Safari's 添加到主屏幕 does for a web page: the website's page (AppLinks.addToHomeScreen) takes the
/// name and icon from what follows its `#`, and when opened from the home screen goes on to one of
/// the app's links: `dsh://app/<id>` for an app of 我的应用 (`id=`), `dsh://web` for the 网页版
/// (`to=web`). The fragment never reaches the server. The icon is drawn here: Safari's canvas does
/// not draw emoji.
@MainActor
enum HomeScreenShortcut {
    static func add(name: String, items: [URLQueryItem], icon: some View) {
        var fragment = URLComponents()
        fragment.queryItems = items + [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "scheme", value: DshLink.scheme),
        ] + [png(icon).map { URLQueryItem(name: "img", value: $0) }].compactMap { $0 }
        // The page reads it with URLSearchParams, where a bare + is a space.
        let encoded = (fragment.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        guard var components = URLComponents(url: AppLinks.addToHomeScreen, resolvingAgainstBaseURL: false) else { return }
        components.percentEncodedFragment = encoded
        guard let url = components.url else { return }
        Haptics.tap()
        UIApplication.shared.open(url)
    }

    /// The 网页版: tapping the icon opens the app straight on it.
    static func addWeb() {
        add(name: String(localized: "网页版"), items: [URLQueryItem(name: "to", value: "web")], icon: WebIcon())
    }

    /// The icon, 180 points square and edge to edge (iOS rounds the corners), as base64url PNG.
    private static func png(_ icon: some View) -> String? {
        let renderer = ImageRenderer(content: icon.frame(width: 180, height: 180).clipped())
        renderer.scale = 1
        guard let data = renderer.uiImage?.pngData() else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// The app's icon as the user picked it, with a globe: the same app, opened on its 网页版. The
/// badge sits clear of the corners the home screen rounds off.
private struct WebIcon: View {
    var body: some View {
        Image(AppIconChoice.current.preview)
            .resizable()
            .scaledToFill()
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "globe")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(Color(red: 0.04, green: 0.52, blue: 1)))
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .padding(14)
            }
    }
}
