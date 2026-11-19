import SwiftUI

/// 余额页：直接查 DeepSeek 的账户余额。
/// 余额接口要一个 key，所以这里单独存一份（存在本机 UserDefaults，不上传）。
struct BalancePage: View {
    @State private var key: String = UserDefaults.standard.string(forKey: "xidai.balance.key") ?? ""
    @State private var loading = false
    @State private var error: String?
    @State private var infos: [BalanceInfo] = []

    private struct BalanceResponse: Decodable {
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfo]?
        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    struct BalanceInfo: Decodable, Identifiable {
        let currency: String
        let totalBalance: String
        let grantedBalance: String
        let toppedUpBalance: String
        var id: String { currency }
        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    var body: some View {
        List {
            Section {
                SecureField("DeepSeek API Key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { save(); Task { await fetch() } }
                Button {
                    save()
                    Task { await fetch() }
                } label: {
                    HStack {
                        Text(loading ? "查询中…" : "查询余额")
                        Spacer()
                        if loading { ProgressView() }
                    }
                }
                .disabled(loading || key.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("账户")
            } footer: {
                Text("只用来读你自己的余额，存在本机。查询走 https://api.deepseek.com/user/balance。")
            }

            if let error {
                Section("查询结果") {
                    Text(error).foregroundStyle(Palette.removed)
                }
            }

            if !infos.isEmpty {
                Section("余额") {
                    ForEach(infos) { info in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("共剩").foregroundStyle(Palette.secondary)
                                Spacer()
                                Text("\(info.totalBalance) \(info.currency.uppercased())")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                            }
                            HStack(spacing: 14) {
                                Label("充值 \(info.toppedUpBalance)", systemImage: "creditcard")
                                Label("赠送 \(info.grantedBalance)", systemImage: "gift")
                            }
                            .font(.footnote)
                            .foregroundStyle(Palette.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Text("余额与扣费由 DeepSeek 账户管理，App 只读取显示。用量球已移除，之前那栏「显示用量」也一起去掉了。")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .navigationTitle("余额")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !infos.isEmpty || loading { return }
            if !key.isEmpty { await fetch() }
        }
    }

    private func save() {
        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "xidai.balance.key")
    }

    private func fetch() async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loading = true
        error = nil
        defer { loading = false }

        guard let url = URL(string: "https://api.deepseek.com/user/balance") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                error = "接口返回 \(code)：\(text.prefix(200))"
                return
            }
            let decoded = try JSONDecoder().decode(BalanceResponse.self, from: data)
            infos = decoded.balanceInfos ?? []
            if infos.isEmpty { error = "没有返回余额信息" }
        } catch {
            self.error = "查询失败：\(error.localizedDescription)"
        }
    }
}
