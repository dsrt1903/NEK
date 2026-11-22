import SwiftUI

@main
struct NEKApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @ViewState private var session: Session?
    @ViewState private var leaving = false
    @ViewState private var logoutError = ""
    private let api = API()

    var body: some View {
        NavigationStack {
            if let session {
                Group {
                    if session.account.isAdmin {
                        ScheduleView(session: session, expire: clearSession)
                    } else {
                        TabView {
                            BookView(session: session, expire: clearSession)
                                .tabItem { Label("Запись", systemImage: "calendar.badge.plus") }
                            VisitsView(session: session, expire: clearSession)
                                .tabItem { Label("Мои визиты", systemImage: "list.bullet.rectangle") }
                        }
                    }
                }
                .navigationTitle(session.account.isAdmin ? "Расписание" : "NEK")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Выйти", action: logout).disabled(leaving)
                    }
                }
            } else {
                LoginView { session = $0 }.navigationBarHidden(true)
            }
        }
        .tint(NEK.brand)
        .alert("Не удалось выйти", isPresented: Binding(
            get: { !logoutError.isEmpty }, set: { if !$0 { logoutError = "" } }
        )) {
            Button("Выйти на этом устройстве", role: .destructive, action: clearSession)
            Button("Остаться", role: .cancel) {}
        } message: { Text(logoutError) }
    }

    private func clearSession() { session = nil }

    private func logout() {
        guard let session else { return }
        leaving = true
        Task {
            defer { leaving = false }
            do {
                try await api.signOut(session.token)
                clearSession()
            } catch let error as APIError where error.status == 401 {
                clearSession()
            } catch {
                logoutError = error.localizedDescription
            }
        }
    }
}

struct LoginView: View {
    var signedIn: (Session) -> Void
    @ViewState private var login = ""
    @ViewState private var password = ""
    @ViewState private var working = false
    @ViewState private var error = ""
    private let api = API()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "sparkle").font(.title2).foregroundStyle(NEK.brand)
                    Text("NEK").font(.system(size: 65, weight: .regular, design: .serif))
                    Text("Студия лазерной эпиляции").font(.title3).foregroundStyle(NEK.muted)
                }
                NEKCard {
                    Text("Вход").font(.title2.bold())
                    TextField("Логин", text: $login)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("login")
                    SecureField("Пароль", text: $password)
                        .textContentType(.password).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("password").onSubmit(signIn)
                    NEKButton(title: working ? "Входим…" : "Войти", action: signIn)
                        .disabled(working || login.isEmpty || password.isEmpty)
                        .opacity(working || login.isEmpty || password.isEmpty ? 0.5 : 1)
                    MessageLine(error, symbol: "exclamationmark.circle")
                }
                Text("Учебный режим с вымышленными данными.").font(.footnote).foregroundStyle(NEK.muted)
                HStack {
                    demoButton("Клиент", login: "client")
                    Spacer()
                    demoButton("Администратор", login: "admin")
                }
            }
            .padding(22).padding(.top, 40).frame(maxWidth: 570)
            .frame(maxWidth: .infinity)
        }
        .background(NEK.background.ignoresSafeArea()).foregroundStyle(NEK.ink)
    }

    private func demoButton(_ label: String, login name: String) -> some View {
        Button(label) { login = name; password = name + "-demo"; signIn() }
            .font(.subheadline.bold()).disabled(working)
    }

    private func signIn() {
        guard !login.isEmpty, !password.isEmpty, !working else { return }
        let credentials = ["login": login, "password": password]
        working = true
        error = ""
        Task {
            defer { working = false }
            do {
                let session: Session = try await api.request("session", method: "POST", body: credentials)
                signedIn(session)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct MessageLine: View {
    let message: String
    let symbol: String
    init(_ message: String, symbol: String) { self.message = message; self.symbol = symbol }
    var body: some View {
        if !message.isEmpty {
            Label(message, systemImage: symbol).font(.subheadline).foregroundStyle(NEK.muted)
        }
    }
}

struct StudioPage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(18).frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(NEK.background.ignoresSafeArea()).foregroundStyle(NEK.ink)
    }
}

struct BookingRow: View {
    let booking: Booking
    var showClient = false

    var body: some View {
        NEKCard {
            Text(StudioDate.time(booking.startsAt) + " – " + StudioDate.time(booking.endsAt))
                .font(.system(.headline, design: .monospaced)).foregroundStyle(NEK.brand)
            Text(booking.serviceName).font(.headline)
            Label(booking.masterName, systemImage: "person").font(.subheadline).foregroundStyle(NEK.muted)
            if showClient {
                Label(booking.clientName, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline).foregroundStyle(NEK.muted)
            }
        }
    }
}
