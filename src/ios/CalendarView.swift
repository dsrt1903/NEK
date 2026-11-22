import SwiftUI

struct ScheduleView: View {
    let session: Session
    var expire: () -> Void

    @ViewState private var catalog: Catalog?
    @ViewState private var day = ""
    @ViewState private var rows: [Booking] = []
    @ViewState private var displayedDay = ""
    @ViewState private var error = ""
    private let api = API()

    var body: some View {
        StudioPage {
            Text("Календарь студии").font(.system(.largeTitle, design: .serif))
            if let catalog {
                NEKCard {
                    Picker("Дата", selection: $day) {
                        ForEach(catalog.days, id: \.self) { Text(StudioDate.day($0)).tag($0) }
                    }.pickerStyle(.menu)
                }
                if displayedDay != day && error.isEmpty { ProgressView() }
                if error.isEmpty, displayedDay == day {
                    if rows.isEmpty {
                        NEKCard { Text("На этот день записей пока нет.").foregroundStyle(NEK.muted) }
                    }
                    ForEach(rows) { BookingRow(booking: $0, showClient: true) }
                }
            } else if error.isEmpty {
                ProgressView()
            }
            if !error.isEmpty {
                NEKCard {
                    MessageLine(error, symbol: "exclamationmark.circle")
                    Button("Повторить") {
                        Task { if catalog == nil { await loadCatalog() } else { await loadDay(day) } }
                    }
                }
            }
        }
        .task { if catalog == nil { await loadCatalog() } }
        .task(id: day) { if !day.isEmpty { await loadDay(day) } }
        .refreshable { if catalog == nil { await loadCatalog() } else { await loadDay(day) } }
    }

    @MainActor private func loadCatalog() async {
        error = ""
        do {
            let values: Catalog = try await api.request("catalog", token: session.token)
            day = values.defaultDay
            catalog = values
        } catch {
            if !Task.isCancelled { report(error) }
        }
    }

    @MainActor private func loadDay(_ current: String) async {
        error = ""
        do {
            let result: [Booking] = try await api.request("schedule", token: session.token, query: ["day": current])
            guard current == day, !Task.isCancelled else { return }
            rows = result
            displayedDay = current
        } catch {
            if current == day, !Task.isCancelled { report(error) }
        }
    }

    private func report(_ failure: Error) {
        if (failure as? APIError)?.status == 401 { expire() } else { error = failure.localizedDescription }
    }
}

struct VisitsView: View {
    let session: Session
    var expire: () -> Void

    @ViewState private var rows: [Booking]?
    @ViewState private var error = ""
    private let api = API()

    var body: some View {
        StudioPage {
            Text("Мои визиты").font(.system(.largeTitle, design: .serif))
            if !error.isEmpty {
                NEKCard {
                    MessageLine(error, symbol: "exclamationmark.circle")
                    Button("Повторить") { Task { await load() } }
                }
            } else if let rows {
                if rows.isEmpty { NEKCard { Text("У вас пока нет записей.").foregroundStyle(NEK.muted) } }
                ForEach(rows) { booking in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(StudioDate.bookingDay(booking.startsAt)).font(.subheadline.bold())
                        BookingRow(booking: booking)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        error = ""
        do {
            rows = try await api.request("bookings", token: session.token)
        } catch let failure as APIError where failure.status == 401 {
            expire()
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
