import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: LoginMode = .pos
    @State private var orgId = "DEMO"
    @State private var shopId = "YGN-MAIN"
    @State private var userId = "OWNER"
    @State private var password = "demo"
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(LoginMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Credentials") {
                    TextField("Org ID", text: $orgId)
                        .textInputAutocapitalization(.characters)
                    if mode == .pos {
                        TextField("Shop ID", text: $shopId)
                            .textInputAutocapitalization(.characters)
                    }
                    TextField("User ID", text: $userId)
                        .textInputAutocapitalization(.characters)
                    SecureField("Password", text: $password)
                }

                if let error = model.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        isSigningIn = true
                        Task {
                            await model.signIn(mode: mode, orgId: orgId, shopId: shopId, userId: userId, password: password)
                            isSigningIn = false
                        }
                    } label: {
                        HStack {
                            Text(isSigningIn ? "Signing in..." : "Sign In")
                            Spacer()
                            if isSigningIn { ProgressView() }
                        }
                    }
                    .disabled(isSigningIn || orgId.isEmpty || userId.isEmpty || password.isEmpty || (mode == .pos && shopId.isEmpty))
                }
            }
            .navigationTitle("ZayFlow Sign In")
        }
    }
}
