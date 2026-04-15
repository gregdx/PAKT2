import SwiftUI
import UIKit

// MARK: - Swipe to dismiss wrapper (for fullScreenCover chat views)

struct SwipeDismissView<Content: View>: View {
    let content: Content
    let onDismiss: () -> Void
    @State private var offset: CGFloat = 0

    init(@ViewBuilder content: () -> Content, onDismiss: @escaping () -> Void) {
        self.content = content()
        self.onDismiss = onDismiss
    }

    var body: some View {
        content
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dismiss if started from left edge
                        if value.startLocation.x < 40 && value.translation.width > 0 {
                            offset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        if value.startLocation.x < 40 && value.translation.width > 100 {
                            // Slide far enough off-screen on any device. A
                            // hardcoded 1000pt avoids both the deprecated
                            // `UIScreen.main` and the faff of hopping through
                            // the window scene just to read a width.
                            withAnimation(.easeOut(duration: 0.25)) {
                                offset = 1000
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onDismiss()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = 0
                            }
                        }
                    }
            )
            .background(Theme.bg.ignoresSafeArea())
    }
}

// MARK: - Username cache (resolves empty names from Apple Sign In users)

enum UsernameCache {
    private static var cache: [String: String] = [:]

    /// Store a known uid → name mapping
    static func store(uid: String, name: String) {
        guard !uid.isEmpty, !name.isEmpty, name != uid, name.count > 2 else { return }
        cache[uid] = name
    }

    /// Resolve a name: use provided if valid, else cache, else truncated uid
    static func resolve(uid: String, name: String?) -> String {
        if let n = name, !n.isEmpty, n != uid, n.count > 2 { return n }
        if let cached = cache[uid] { return cached }
        return String(uid.prefix(8))
    }
}

// MARK: - UUID Identifiable (pour sheet(item:))
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Swipe-back

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Logger

import os.log

enum Log {
    private static let logger = Logger(subsystem: "com.PAKT2", category: "app")

    static func d(_ message: String) {
        // Use .info instead of .debug so the message survives Release builds
        // too — we need these diagnostics to verify DAR IPC in Release.
        logger.info("\(message, privacy: .public)")
    }
    static func i(_ message: String) { logger.info("\(message, privacy: .public)") }
    static func e(_ message: String) { logger.error("\(message, privacy: .public)") }
}


// MARK: - Cached Async Image

private final class _TimedImage {
    let image: UIImage
    let fetchedAt: Date
    init(_ image: UIImage) { self.image = image; self.fetchedAt = Date() }
}

private let _venueImageCache = NSCache<NSString, _TimedImage>()

private let _venueImageTTL: TimeInterval = 600

enum ImageCache {
    static func invalidate(url: URL) {
        _venueImageCache.removeObject(forKey: url.absoluteString as NSString)
    }
    static func invalidateAll() {
        _venueImageCache.removeAllObjects()
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage? = nil

    var body: some View {
        SwiftUI.Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Color.clear
            }
        }
        // `.task(id:)` reruns — and cancels the prior task — every time the
        // URL changes. Switching to this from `.onAppear` fixes the "same
        // preview image lingers when user taps a different map pin" bug:
        // SwiftUI was reusing the view instance with a new URL but never
        // re-firing onAppear, so the old UIImage stayed on screen.
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else {
            image = nil
            return
        }
        let key = url.absoluteString as NSString
        if let cached = _venueImageCache.object(forKey: key),
           Date().timeIntervalSince(cached.fetchedAt) < _venueImageTTL {
            image = cached.image
            return
        }
        // Clear stale content so the old image doesn't flash under the new one.
        image = nil
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        _venueImageCache.setObject(_TimedImage(img), forKey: key)
        image = img
    }
}

// MARK: - Constants

/// 16 waking hours × 60 = 960 minutes
let kWakingMinutesPerDay: Double = 960.0

enum AppConfig {
    static let keychainGroup = "9U5UZW39LQ.com.PAKT2"
    static let appGroupID = "group.com.PAKT2"
    static let apiBaseURL = "https://pakt-api.fly.dev/v1"
    static let wsBaseURL = "wss://pakt-api.fly.dev/v1/ws"
}

/// UserDefaults keys for profile cache
enum UDKey {
    static let lastUID         = "lastUID"
    static let todayMinutes    = "pakt_todayMinutes"
    static let todayDate       = "pakt_todayDate"
    static let weekAvg         = "pakt_weekAvg"
    static let monthAvg        = "pakt_monthAvg"
    static let catSocial       = "pakt_catSocial"
    static let catSocialDate   = "pakt_catSocialDate"
    static let historyRaw      = "pakt_historyRaw"
}

/// Max profile photo dimension before base64 encoding
let kMaxPhotoSize: CGFloat = 300

// MARK: - Theme — stark, minimal, Trade Republic-inspired

struct Theme {
    static let bg        = Color(UIColor.systemBackground)
    static let bgWarm    = Color(UIColor.systemGray6)
    static let bgCard    = Color(UIColor.secondarySystemBackground)

    static let text      = Color(UIColor.label)
    static let textMuted = Color(UIColor.secondaryLabel)
    static let textFaint = Color(UIColor.tertiaryLabel)

    static let border      = Color(UIColor.separator)
    static let borderLight = Color(UIColor.opaqueSeparator)
    static let separator   = Color(UIColor.separator)

    static let green  = Color(red: 0.00, green: 0.75, blue: 0.36)
    static let red    = Color(red: 0.93, green: 0.18, blue: 0.09)
    static let orange = Color(red: 1.00, green: 0.60, blue: 0.00)
    static let blue   = Color(red: 0.35, green: 0.48, blue: 0.95)

    static let cardBg     = bgCard
    static let cardBorder = border

    // Tab bar background — s'adapte au dark/light mode
    static let tabBar = Color(UIColor.systemBackground)
}

// MARK: - Liquid Glass

struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 14
    var style: LiquidGlassStyle = .regular

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    ZStack {
                        // Blur glass effect avec Material
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(style.material)
                        
                        // Subtile gradient de fond pour profondeur
                        LinearGradient(
                            colors: style.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .opacity(style.gradientOpacity)
                        .cornerRadius(cornerRadius)
                    }
                    .shadow(color: .black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(style.borderTopOpacity),
                                    Color.white.opacity(style.borderBottomOpacity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: style.borderWidth
                        )
                )
        }
    }
}

enum LiquidGlassStyle {
    case ultraThin    // Très transparent, presque invisible (messages)
    case thin         // Léger et translucide
    case regular      // Normal, équilibré
    case thick        // Plus opaque, plus visible
    case solid        // Presque opaque
    
    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin:      return .thinMaterial
        case .regular:   return .regularMaterial
        case .thick:     return .thickMaterial
        case .solid:     return .thickMaterial
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .ultraThin: return [Color.white.opacity(0.15), Color.white.opacity(0.08)]
        case .thin:      return [Color.white.opacity(0.18), Color.white.opacity(0.10)]
        case .regular:   return [Color.white.opacity(0.22), Color.white.opacity(0.12)]
        case .thick:     return [Color.white.opacity(0.28), Color.white.opacity(0.16)]
        case .solid:     return [Color.white.opacity(0.35), Color.white.opacity(0.22)]
        }
    }
    
    var gradientOpacity: Double {
        switch self {
        case .ultraThin: return 0.6
        case .thin:      return 0.7
        case .regular:   return 0.8
        case .thick:     return 0.85
        case .solid:     return 0.95
        }
    }
    
    var borderTopOpacity: Double {
        switch self {
        case .ultraThin: return 0.35
        case .thin:      return 0.40
        case .regular:   return 0.45
        case .thick:     return 0.50
        case .solid:     return 0.55
        }
    }
    
    var borderBottomOpacity: Double {
        switch self {
        case .ultraThin: return 0.10
        case .thin:      return 0.12
        case .regular:   return 0.15
        case .thick:     return 0.18
        case .solid:     return 0.22
        }
    }
    
    var borderWidth: CGFloat {
        switch self {
        case .ultraThin: return 1.0
        case .thin:      return 1.0
        case .regular:   return 1.2
        case .thick:     return 1.5
        case .solid:     return 2.0
        }
    }
    
    var shadowOpacity: Double {
        switch self {
        case .ultraThin: return 0.08
        case .thin:      return 0.10
        case .regular:   return 0.12
        case .thick:     return 0.15
        case .solid:     return 0.20
        }
    }
    
    var shadowRadius: CGFloat {
        switch self {
        case .ultraThin: return 8
        case .thin:      return 10
        case .regular:   return 12
        case .thick:     return 14
        case .solid:     return 16
        }
    }
    
    var shadowY: CGFloat {
        switch self {
        case .ultraThin: return 1
        case .thin:      return 2
        case .regular:   return 3
        case .thick:     return 4
        case .solid:     return 5
        }
    }
}

extension View {
    /// Applique l'effet Liquid Glass avec un style spécifique
    func liquidGlass(cornerRadius: CGFloat = 14, style: LiquidGlassStyle = .regular) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, style: style))
    }
}

// MARK: - Conditional Refreshable

struct RefreshableIfNotSheet: ViewModifier {
    let isSheet: Bool
    let action: () async -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSheet {
            content
        } else {
            content.refreshable { await action() }
        }
    }
}

// MARK: - Typography — no serif, bold for impact

struct AppFont {
    // In PAKT2, "serif" = bold system font for big numbers
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let w: Font.Weight = (weight == .regular) ? .bold : weight
        return .system(size: size, weight: w, design: .default)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Member color

func memberColor(rank: Int, total: Int, mode: GameMode) -> Color {
    if mode == .collective { return Theme.textMuted }
    if rank == 1           { return Theme.green }
    if rank == total       { return Theme.red }
    let palette: [Color] = [
        Color(red: 0.20, green: 0.44, blue: 0.90),
        Color(red: 0.75, green: 0.44, blue: 0.10),
        Color(red: 0.52, green: 0.18, blue: 0.72),
    ]
    return palette[max(0, min(rank - 2, palette.count - 1))]
}

// MARK: - Curve shape

struct CurveShape: Shape {
    let points  : [Int]
    let maxValue: Int
    let minValue: Int

    init(points: [Int], maxValue: Int, minValue: Int = 0) {
        self.points   = points
        self.maxValue = maxValue
        self.minValue = minValue
    }

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        var path = Path()
        func y(_ v: Int) -> CGFloat {
            let range = CGFloat(maxValue - minValue)
            let ratio = range > 0 ? CGFloat(v - minValue) / range : 0.5
            return rect.height * (1 - 0.08) - ratio * rect.height * 0.84
        }
        let step = rect.width / CGFloat(points.count - 1)
        path.move(to: CGPoint(x: 0, y: y(points[0])))
        for i in 1..<points.count {
            let cx = CGFloat(i) * step;   let cy = y(points[i])
            let px = CGFloat(i-1) * step; let py = y(points[i-1])
            path.addCurve(
                to:       CGPoint(x: cx, y: cy),
                control1: CGPoint(x: px + step * 0.4, y: py),
                control2: CGPoint(x: cx - step * 0.4, y: cy)
            )
        }
        return path
    }
}

// MARK: - Period picker — underline style

struct PeriodPicker: View {
    @Binding var selected: Period
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases, id: \.self) { p in
                Button(action: { withAnimation(.easeInOut(duration: 0.18)) { selected = p } }) {
                    VStack(spacing: 6) {
                        Text(p.rawValue)
                            .font(.system(size: 15, weight: selected == p ? .semibold : .regular))
                            .foregroundColor(selected == p ? Theme.text : Theme.textFaint)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(selected == p ? Theme.text : Color.clear)
                            .frame(height: 2)
                    }
                }
            }
        }
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let label : String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.text.opacity(0.08))
                )
                .liquidGlass(cornerRadius: 16, style: .ultraThin)
        }
    }
}

// MARK: - Divider

struct AppDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 0.5)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
    }
}

// MARK: - Section title

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.textFaint)
            .tracking(1.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
    }
}

// MARK: - Form field

struct AppField: View {
    let label    : String
    @Binding var text: String
    var keyboard : UIKeyboardType = .default
    var secure   : Bool           = false
    var uppercase: Bool           = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textFaint)
                .tracking(1.2)
            if secure {
                SecureField("", text: $text)
                    .font(.system(size: 20)).foregroundColor(Theme.text)
            } else {
                TextField("", text: $text)
                    .font(.system(size: 20)).foregroundColor(Theme.text)
                    .keyboardType(keyboard)
                    .autocapitalization(uppercase ? .allCharacters : .none)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

// MARK: - Stat block

struct StatBlock: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
            Text(label.uppercased())
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textFaint)
                .tracking(0.8)
        }
    }
}

// MARK: - Avatar

// In-memory + disk photo cache for avatars
private var _photoCache: [String: UIImage] = [:]
private let _photoCacheLock = NSLock()
private var _photoFetching: Set<String> = []
private var _photoFailedAt: [String: Date] = [:]  // track when fetch failed to allow retry
private let _avatarCacheDir: URL? = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("avatars")
    if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    return dir
}()

func cachedPhoto(for uid: String) -> UIImage? {
    // `withLock` is the async-safe scoped API; calling `.lock()`/`.unlock()`
    // directly is gated behind a Swift 6 error because it can strand the
    // lock if a suspension point slips between the two calls.
    _photoCacheLock.withLock {
        if let img = _photoCache[uid] { return img }
        if let dir = _avatarCacheDir,
           let data = try? Data(contentsOf: dir.appendingPathComponent("\(uid).jpg")),
           let img = UIImage(data: data) {
            _photoCache[uid] = img
            return img
        }
        return nil
    }
}
func cachePhoto(_ img: UIImage, for uid: String) {
    _photoCacheLock.withLock {
        _photoCache[uid] = img
        _photoFetching.remove(uid)
        _photoFailedAt.removeValue(forKey: uid)
    }
    // Disk write happens outside the lock: the in-memory caches are
    // already consistent and I/O doesn't need to block other readers.
    if let dir = _avatarCacheDir, let data = img.jpegData(compressionQuality: 0.7) {
        try? data.write(to: dir.appendingPathComponent("\(uid).jpg"))
    }
}
func isPhotoFetching(_ uid: String) -> Bool {
    _photoCacheLock.withLock { _photoFetching.contains(uid) }
}
func markPhotoFetching(_ uid: String) {
    _photoCacheLock.withLock { _ = _photoFetching.insert(uid) }
}
func markPhotoFailed(_ uid: String) {
    _photoCacheLock.withLock {
        _photoFetching.remove(uid)
        _photoFailedAt[uid] = Date()
    }
}
func shouldRetryPhoto(_ uid: String) -> Bool {
    _photoCacheLock.withLock {
        guard let failedAt = _photoFailedAt[uid] else { return true }
        return Date().timeIntervalSince(failedAt) > 60
    }
}
func shouldRevalidatePhoto(_ uid: String) -> Bool {
    guard let dir = _avatarCacheDir else { return true }
    let file = dir.appendingPathComponent("\(uid).jpg")
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let modified = attrs[.modificationDate] as? Date else { return true }
    // Revalidate if cached file is older than 5 minutes
    return Date().timeIntervalSince(modified) > 300
}

/// Force clear all caches (for pull-to-refresh or debug)
func clearAllPhotoCaches() {
    _photoCacheLock.withLock {
        _photoCache.removeAll()
        _photoFetching.removeAll()
        _photoFailedAt.removeAll()
    }
    if let dir = _avatarCacheDir {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

struct AvatarView: View {
    let name  : String
    let size  : CGFloat
    let color : Color
    var uid   : String = ""
    var isMe  : Bool   = false
    @EnvironmentObject var appState: AppState
    @State private var remotePhoto: UIImage? = nil

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.10)).frame(width: size, height: size)
            if isMe, let img = appState.profileUIImage {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else if let img = remotePhoto {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.40, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .onAppear { loadPhoto() }
        .onChange(of: uid) { _, _ in
            remotePhoto = nil
            loadPhoto()
        }
    }

    private func loadPhoto() {
        guard !isMe, !uid.isEmpty else { return }
        // Show cached photo immediately
        if let cached = cachedPhoto(for: uid) {
            if remotePhoto == nil { remotePhoto = cached }
            // Don't re-fetch if we already have a cached version showing
            guard shouldRevalidatePhoto(uid) else { return }
        }
        // Fetch from server if not already fetching and retry is allowed
        guard !isPhotoFetching(uid), shouldRetryPhoto(uid) else { return }
        markPhotoFetching(uid)
        Task {
            if let img = await AuthManager.shared.fetchProfilePhoto(uid: uid) {
                cachePhoto(img, for: uid)
                await MainActor.run { remotePhoto = img }
            } else {
                markPhotoFailed(uid)
            }
        }
    }
}

// MARK: - Photo-only avatar (no AppState dependency)

/// Compact avatar that shows a user's profile photo when available, falling
/// back to the first letter of their name. Independent of `AppState` so it
/// works inside sheets and other contexts where the environment object may
/// not be injected.
struct FriendPhotoCircle: View {
    let uid: String
    let name: String
    var size: CGFloat = 36
    var ringColor: Color? = nil
    var ringWidth: CGFloat = 2.5

    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Circle().fill(Theme.bgCard).frame(width: size, height: size)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(Theme.text)
            }
        }
        .overlay(
            SwiftUI.Group {
                if let ringColor {
                    Circle().strokeBorder(ringColor, lineWidth: ringWidth)
                }
            }
        )
        .onAppear(perform: load)
        .onChange(of: uid) { _, _ in
            image = nil
            load()
        }
    }

    private func load() {
        guard !uid.isEmpty else { return }
        if let cached = cachedPhoto(for: uid) {
            if image == nil { image = cached }
            guard shouldRevalidatePhoto(uid) else { return }
        }
        guard !isPhotoFetching(uid), shouldRetryPhoto(uid) else { return }
        markPhotoFetching(uid)
        Task {
            if let img = await AuthManager.shared.fetchProfilePhoto(uid: uid) {
                cachePhoto(img, for: uid)
                await MainActor.run { image = img }
            } else {
                markPhotoFailed(uid)
            }
        }
    }
}

// MARK: - Universal tappable avatar

/// Tappable avatar that opens `FriendProfileView` for any user in the app.
/// Use this everywhere an avatar is displayed so every member/friend photo
/// becomes a link to that user's profile (one of the April-14 product asks).
///
/// Pass the uid (required for the profile to load). If the uid matches a
/// known friend, the full `AppUser` is reused; otherwise a minimal stub
/// is built so the profile sheet can still fetch the rest from the backend.
struct UserAvatarButton: View {
    let uid: String
    let name: String
    var size: CGFloat = 36
    var color: Color = Theme.bgCard
    var isMe: Bool = false
    /// When true, tapping is a no-op (useful for demo/empty-uid members).
    var disabled: Bool = false

    @State private var showProfile = false
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            guard !disabled, !uid.isEmpty, !isMe else { return }
            showProfile = true
        } label: {
            AvatarView(name: name, size: size, color: color, uid: uid, isMe: isMe)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            if let user = resolvedUser() {
                NavigationStack {
                    FriendProfileView(user: user)
                        .environmentObject(appState)
                }
            }
        }
    }

    private func resolvedUser() -> AppUser? {
        if let friend = FriendManager.shared.friends.first(where: { $0.id == uid }) {
            return friend
        }
        guard !uid.isEmpty else { return nil }
        return AppUser(id: uid, firstName: name, email: "", goalHours: 3.0)
    }
}

// MARK: - Placeholder

extension View {
    func placeholder<C: View>(
        when show: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> C
    ) -> some View {
        ZStack(alignment: alignment) {
            content().opacity(show ? 1 : 0)
            self
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
