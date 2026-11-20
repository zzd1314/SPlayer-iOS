import Foundation

/// 登录态管理：Cookie 存 Keychain，账号信息缓存在内存
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var cookie: String?
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var profileError: String?

    private let keychainKey = "netease-cookie"

    var isLoggedIn: Bool { cookie != nil }

    init() {
        cookie = Keychain.read(keychainKey)
    }

    /// 扫码成功后写入登录态
    func signIn(cookie: String) async {
        self.cookie = cookie
        Keychain.save(cookie, for: keychainKey)
        await refreshProfile()
    }

    func signOut() {
        cookie = nil
        profile = nil
        profileError = nil
        Keychain.delete(keychainKey)
    }

    func refreshProfile() async {
        guard let cookie else { return }
        isLoadingProfile = true
        profileError = nil
        defer { isLoadingProfile = false }

        do {
            let account = try await NeteaseAPI().account(cookie: cookie)
            profile = account
            if account == nil {
                // Cookie 已失效
                signOut()
            }
        } catch {
            profileError = error.localizedDescription
        }
    }
}
