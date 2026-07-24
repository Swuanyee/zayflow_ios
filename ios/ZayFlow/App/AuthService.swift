import Foundation

struct AuthService: Sendable {
    struct LoginRequest: Encodable {
        let mode: String
        let orgId: String
        let shopId: String?
        let userId: String
        let password: String
        let deviceInstallationId: String
    }

    struct LoginResponse: Decodable {
        let entitlements: AuthSession
    }

    var baseURL: URL {
        #if targetEnvironment(simulator)
        URL(string: "http://127.0.0.1:3000")!
        #elseif DEBUG
        URL(string: "http://192.168.73.254:3000")!
        #else
        URL(string: "https://api.zayflow.app")!
        #endif
    }

    func login(mode: LoginMode, orgId: String, shopId: String?, userId: String, password: String) async throws -> AuthSession {
        #if DEBUG
        if let session = localDemoSession(mode: mode, orgId: orgId, shopId: shopId, userId: userId, password: password) {
            return session
        }
        #endif

        var request = URLRequest(url: baseURL.appending(path: "/api/auth/v1/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let installationId = UserDefaults.standard.string(forKey: "deviceInstallationId") ?? UUID().uuidString
        UserDefaults.standard.set(installationId, forKey: "deviceInstallationId")
        let body = LoginRequest(
            mode: mode.rawValue,
            orgId: orgId,
            shopId: shopId,
            userId: userId,
            password: password,
            deviceInstallationId: installationId
        )
        request.httpBody = try JSONEncoder.zayFlow.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Sign in failed"
            throw AuthError.rejected(message)
        }
        return try JSONDecoder.zayFlow.decode(LoginResponse.self, from: data).entitlements
    }

    #if DEBUG
    private func localDemoSession(mode: LoginMode, orgId: String, shopId: String?, userId: String, password: String) -> AuthSession? {
        guard orgId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DEMO",
              password == "demo" else { return nil }

        let normalizedUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedShopId = shopId?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let shops = [
            AuthSession.Shop(id: UUID(uuidString: "21000000-0000-4000-8000-000000000001")!, code: "YGN-MAIN", name: "Yangon Main"),
            AuthSession.Shop(id: UUID(uuidString: "21000000-0000-4000-8000-000000000002")!, code: "HLEDAN", name: "Hledan Express")
        ]
        let selectedShop: AuthSession.Shop?
        if mode == .pos {
            guard let normalizedShopId,
                  let shop = shops.first(where: { $0.code == normalizedShopId || $0.id.uuidString.uppercased() == normalizedShopId }) else {
                return nil
            }
            selectedShop = shop
        } else {
            selectedShop = nil
        }

        let user: AuthSession.User
        let permittedShops: [AuthSession.Shop]
        switch normalizedUserId {
        case "OWNER":
            user = AuthSession.User(id: UUID(uuidString: "80000000-0000-4000-8000-000000000001")!, userCode: "OWNER", displayName: "Demo Owner", role: .owner, canSell: true, canIntake: true)
            permittedShops = shops
        case "ADMIN":
            user = AuthSession.User(id: UUID(uuidString: "80000000-0000-4000-8000-000000000002")!, userCode: "ADMIN", displayName: "Demo Admin", role: .admin, canSell: true, canIntake: true)
            permittedShops = shops
        case "MANAGER":
            user = AuthSession.User(id: UUID(uuidString: "80000000-0000-4000-8000-000000000003")!, userCode: "MANAGER", displayName: "Demo Manager", role: .manager, canSell: true, canIntake: true)
            permittedShops = [shops[0]]
        case "CASHIER":
            user = AuthSession.User(id: UUID(uuidString: "80000000-0000-4000-8000-000000000004")!, userCode: "CASHIER", displayName: "Demo Cashier", role: .cashier, canSell: true, canIntake: false)
            permittedShops = [shops[0]]
        default:
            return nil
        }

        if let selectedShop, !permittedShops.contains(where: { $0.id == selectedShop.id }) {
            return nil
        }
        if mode == .organisationDashboard, !user.role.canUseOrganisationDashboard {
            return nil
        }

        let installationId = UserDefaults.standard.string(forKey: "deviceInstallationId") ?? UUID().uuidString
        UserDefaults.standard.set(installationId, forKey: "deviceInstallationId")
        let now = Date()
        return AuthSession(
            mode: mode,
            organization: AuthSession.Organization(id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!, code: "DEMO", name: "ZayFlow Demo Store"),
            shop: selectedShop,
            user: user,
            permittedShops: permittedShops,
            device: AuthSession.Device(installationId: installationId, requiresFullSyncBy: now.addingTimeInterval(7 * 86_400)),
            issuedAt: now
        )
    }
    #endif
}

struct APIError: Decodable {
    let error: String
}

enum AuthError: LocalizedError {
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .rejected(let message): message
        }
    }
}
