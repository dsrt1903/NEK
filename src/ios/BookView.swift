import SwiftUI

private struct Selection: Equatable {
    var serviceId = ""
    var masterId = ""
    var day = ""
    var ready: Bool { !serviceId.isEmpty && !masterId.isEmpty && !day.isEmpty }
    var fields: [String: String] { ["serviceId": serviceId, "masterId": masterId, "day": day] }
}

struct BookView: View {
    let session: Session
    var expire: () -> Void

    @ViewState private var catalog: Catalog?
    @ViewState private var selection = Selection()
    @ViewState private var loadedSelection: Selection?
    @ViewState private var slots: [Slot] = []
    @ViewState private var chosenSlot: Slot?
    @ViewState private var waiting = false
    @ViewState private var listError = ""
    @ViewState private var notice = ""
    @ViewState private var success = false
    private let api = API()

    var body: some View {
        StudioPage {
            VStack(alignment: .leading, spacing: 5) {
                Text("Онлайн-запись").font(.system(.largeTitle, design: .serif))
                Text("Выберите услугу и время").foregroundStyle(NEK.muted)
            }
            if let catalog {
                inputs(catalog).disabled(waiting)
                timePanel
            } else if listError.isEmpty {
                ProgressView()
            } else {
                NEKCard {
                    MessageLine(listError, symbol: "exclamationmark.circle")
                    Button("Повторить") { Task { await loadCatalog() } }
                }
            }
        }
        .task { if catalog == nil { await loadCatalog() } }
        .task(id: selection) {
            let current = selection
            chosenSlot = nil
            if current.ready { await loadSlots(current) }
        }
        .onChange(of: selection) { _, _ in notice = "" }
    }

    private func inputs(_ catalog: Catalog) -> some View {
        NEKCard {
            Text("Визит").font(.headline)
            Picker("Услуга", selection: $selection.serviceId) {
                ForEach(catalog.services) { service in
                    Label(service.name, systemImage: service.icon).tag(service.id)
                }
            }
            if let service = catalog.services.first(where: { $0.id == selection.serviceId }) {
                let price = service.price == 0 ? "бесплатно" : "\(service.price) сомони"
                Text("\(service.duration) мин · \(price)").font(.footnote).foregroundStyle(NEK.muted)
            }
            Picker("Специалист", selection: $selection.masterId) {
                ForEach(catalog.masters) { Text($0.name).tag($0.id) }
            }
            Picker("Дата", selection: $selection.day) {
                ForEach(catalog.days, id: \.self) { Text(StudioDate.day($0)).tag($0) }
            }
        }
        .pickerStyle(.menu)
    }

    private var timePanel: some View {
        NEKCard {
            Text("Свободное время").font(.headline)
            if loadedSelection != selection {
                ProgressView()
            } else if !listError.isEmpty {
                MessageLine(listError, symbol: "exclamationmark.circle")
                Button("Повторить") { Task { await loadSlots(selection) } }.disabled(waiting)
            } else if slots.isEmpty {
                Text("Свободных окон нет. Выберите другой день.").font(.subheadline).foregroundStyle(NEK.muted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                    ForEach(slots) { slot in
                        let selected = chosenSlot?.id == slot.id
                        Button {
                            chosenSlot = slot
                            notice = ""
                        } label: {
                            Text(StudioDate.time(slot.startsAt))
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? NEK.onBrand : NEK.ink)
                                .background(selected ? NEK.brand : NEK.soft, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("availableSlot")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.disabled(waiting)
                if chosenSlot != nil {
                    NEKButton(title: waiting ? "Сохраняем…" : "Подтвердить запись", action: submit)
                        .disabled(waiting)
                }
            }
            MessageLine(notice, symbol: success ? "checkmark.circle.fill" : "exclamationmark.circle")
        }
    }

    @MainActor private func loadCatalog() async {
        listError = ""
        do {
            let values: Catalog = try await api.request("catalog", token: session.token)
            selection = Selection(
                serviceId: values.services.first?.id ?? "", masterId: values.masters.first?.id ?? "",
                day: values.defaultDay
            )
            catalog = values
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { handle(error) { listError = $0 } }
        }
    }

    @MainActor private func loadSlots(_ current: Selection) async {
        guard current == selection else { return }
        loadedSelection = nil
        listError = ""
        do {
            let values: [Slot] = try await api.request("slots", token: session.token, query: current.fields)
            guard !Task.isCancelled, current == selection else { return }
            slots = values
        } catch {
            guard !Task.isCancelled, current == selection else { return }
            handle(error) { listError = $0 }
        }
        loadedSelection = current
    }

    private func submit() {
        guard let slot = chosenSlot, loadedSelection == selection, !waiting else { return }
        let current = selection
        var body = current.fields
        body["startsAt"] = slot.startsAt
        waiting = true
        notice = ""
        Task {
            defer { waiting = false }
            do {
                let row: Booking = try await api.request("bookings", method: "POST", token: session.token, body: body)
                success = true
                notice = "Запись подтверждена на \(StudioDate.time(row.startsAt))."
                chosenSlot = nil
                await loadSlots(current)
            } catch {
                success = false
                handle(error) { notice = $0 }
                if (error as? APIError)?.status == 409 {
                    chosenSlot = nil
                    await loadSlots(current)
                }
            }
        }
    }

    private func handle(_ error: Error, display: (String) -> Void) {
        if (error as? APIError)?.status == 401 { expire() } else { display(error.localizedDescription) }
    }
}
