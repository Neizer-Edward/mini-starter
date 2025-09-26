import Hummingbird
import HummingbirdFluent
import FluentKit
import Foundation
import NIOCore 
import ServiceLifecycle 

struct ProjectPollingWorker: Service {
    let app: any ApplicationProtocol
    let fluent: Fluent
    let supabaseService: SupabaseService
    let shortInterval: TimeAmount
    let longInterval: TimeAmount

    func run() async throws {
        app.logger.info("ProjectPollingWorker started")

        var currentInterval = shortInterval

        while !Task.isCancelled {
            do {
                let hasCreatingClients = try await pollCreatingClients()
                currentInterval = hasCreatingClients ? shortInterval : longInterval
            } catch {
                app.logger.error("Polling error: \(error)")
                currentInterval = shortInterval
            }

            try? await Task.sleep(nanoseconds: UInt64(currentInterval.nanoseconds))
        }

        app.logger.info("ProjectPollingWorker stopped")
    }

    private func pollCreatingClients() async throws -> Bool {
        let creatingClientIds: [UUID] = try await fluent.db().withConnection { db in
            try await Client.query(on: db)
                .filter(\.$status == "creating")
                .all()
                .compactMap { $0.id }
        }

        if creatingClientIds.isEmpty {
            app.logger.debug("No clients in 'creating' state. Skipping this interval.")
            return false
        }

        for clientId in creatingClientIds {
          
            try await fluent.db().withConnection { db in
                guard let client = try await Client.find(clientId, on: db),
                      let ref = client.supabaseProjectId else { return }

                do {
                 
                    let status = try await supabaseService.checkProjectStatus(ref: ref)

                    switch status {
                    case .creating:
                        app.logger.info("Client \(client.id?.uuidString ?? "-") still creating...")

                    case .provisioned(let dbHost):
                        app.logger.info("Client \(client.id?.uuidString ?? "-") provisioned with host: \(dbHost)")
                        try await db.transaction { tx in
                            client.dbConnection = "postgres://user:\(client.dbPassword ?? "")@\(dbHost):5432/postgres"
                            client.status = "provisioned"
                            try await client.update(on: tx)
                        }

                    case .failed:
                        app.logger.error("Client \(client.id?.uuidString ?? "-") failed.")
                        try await db.transaction { tx in
                            client.status = "failed"
                            try await client.update(on: tx)
                        }
                    }
                } catch {
                    app.logger.error("Error checking project status for client \(client.id?.uuidString ?? "-"): \(error)")
                }
            }
        }

        return true
    }
}
