// Logging in to the central system in the cloud, keeping things in step, and sharing a field
// with someone who may watch it.
import SwiftUI
import UIKit

struct AccountView: View {
    @ObservedObject var cloud: CloudStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.spacing) {
                    switch cloud.state {
                    case .notConfigured:
                        notConfigured
                    case .loggedOut:
                        loginCard
                    case .loggedIn(let address):
                        accountCard(address)
                        if let config = cloud.config {
                            boxCard(config)
                        }
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Account en cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }

    private var notConfigured: some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(symbol: "icloud.slash", color: .gray, size: 30)
                Text("De cloud is nog niet ingesteld").font(.headline)
            }
            Text("Het centrale systeem draait in Supabase. Zolang het niet is geïnstalleerd, werkt de app gewoon zonder cloud: alles blijft op deze iPhone. Hoe je het installeert, staat in centraal/README.md.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var loginCard: some View {
        Card(spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(symbol: "icloud", color: .blue, size: 30)
                Text("Inloggen").font(.headline)
            }
            Text("Met een account staan je velden, sensormetingen en adviezen ook in de cloud. Je sensorkastjes kunnen er rechtstreeks naartoe sturen, en je kunt anderen laten meekijken.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("E-mailadres", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("Wachtwoord (minstens 6 tekens)", text: $password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
            if let message {
                Notice(text: message, symbol: "info.circle.fill", color: .blue)
            }
            Button {
                run { try await cloud.signIn(email: email, password: password) }
            } label: {
                Label("Inloggen", systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(ActionButtonStyle(color: .actionGo))
            .disabled(busy || email.isEmpty || password.count < 6)
            Button {
                run {
                    let loggedIn = try await cloud.signUp(email: email, password: password)
                    if !loggedIn {
                        message = "Account gemaakt. Je krijgt een e-mail van Supabase: klik op de link om je e-mailadres te bevestigen, en log daarna hier in. (De pagina die na de link opent, mag een foutmelding geven.)"
                    }
                }
            } label: {
                Label("Account maken", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(ActionButtonStyle(color: .blue, prominent: false))
            .disabled(busy || email.isEmpty || password.count < 6)
            if busy { ProgressView().frame(maxWidth: .infinity) }
        }
    }

    private func accountCard(_ address: String) -> some View {
        Card(spacing: 14, tint: .green) {
            HStack(spacing: 10) {
                IconBadge(symbol: "checkmark.icloud.fill", color: .green, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ingelogd").font(.headline)
                    Text(address).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Row(label: "Laatst gesynchroniseerd",
                value: cloud.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "nog niet")
            if let problem = cloud.problem {
                Notice(text: problem)
            }
            Button {
                Task { await cloud.sync() }
            } label: {
                Label(cloud.syncing ? "Bezig…" : "Nu synchroniseren", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(ActionButtonStyle(color: .actionGo))
            .disabled(cloud.syncing)
            Button {
                Task { await cloud.signOut() }
            } label: {
                Label("Uitloggen", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(ActionButtonStyle(color: .gray, prominent: false))
            Text("De app synchroniseert vanzelf als je hem opent: je velden en vluchten gaan naar de cloud; metingen, weer, advies en gedeelde velden komen terug.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// What goes into Instellingen.h of a sensor box that sends straight to the cloud.
    private func boxCard(_ config: CloudConfig) -> some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(symbol: "sensor.fill", color: .teal, size: 30)
                Text("Voor je sensorkastjes").font(.headline)
            }
            Text("Zet deze twee in Instellingen.h van elk kastje. De sleutel per sensor staat bij Sensoren plaatsen en ijken.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            copyRow("CLOUD_PROJECT", config.projectRef)
            copyRow("CLOUD_SLEUTEL", config.key)
        }
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel("Kopieer \(label)")
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        busy = true
        message = nil
        Task {
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}

/// Lets others with a Veldvlucht account watch one of your fields.
struct ShareView: View {
    let field: FieldRecord
    @ObservedObject var cloud: CloudStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var members: [String] = []
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.spacing) {
                    if cloud.isLoggedIn {
                        Card(spacing: 12) {
                            Text("Wie je uitnodigt, ziet dit veld met de sensoren, het weer en het advies. Kijken, niet veranderen. Diegene moet eerst zelf een account maken in Veldvlucht.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            TextField("E-mailadres", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button {
                                act {
                                    message = try await cloud.invite(email, to: field.id)
                                    email = ""
                                }
                            } label: {
                                Label("Uitnodigen", systemImage: "person.badge.plus")
                            }
                            .buttonStyle(ActionButtonStyle(color: .actionGo))
                            .disabled(busy || !email.contains("@"))
                            if let message {
                                Notice(text: message, symbol: "info.circle.fill", color: .blue)
                            }
                        }
                        Card {
                            Text("Mag meekijken").font(.headline)
                            if members.isEmpty {
                                Text("Nog niemand.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            ForEach(members, id: \.self) { member in
                                HStack {
                                    Text(member).font(.subheadline)
                                    Spacer()
                                    Button(role: .destructive) {
                                        act { try await cloud.remove(member, from: field.id) }
                                    } label: {
                                        Image(systemName: "person.badge.minus")
                                    }
                                    .accessibilityLabel("\(member) verwijderen")
                                }
                            }
                        }
                    } else {
                        Card {
                            Notice(text: "Log eerst in bij Account en cloud. Delen gaat via het centrale systeem.", symbol: "icloud", color: .blue)
                        }
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Delen: \(field.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .task { await loadMembers() }
        }
    }

    private func loadMembers() async {
        members = (try? await cloud.members(of: field.id)) ?? []
    }

    private func act(_ action: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await action()
                await loadMembers()
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}
