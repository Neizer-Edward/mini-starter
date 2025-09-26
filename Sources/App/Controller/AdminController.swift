import FluentKit
import Foundation
import Hummingbird
import HummingbirdFluent

struct AdminController {
    typealias Context = AppRequestContext

    let fluent: Fluent
    let supabaseService: SupabaseService
    let organizationId: String  

    func addRoutes(to group: RouterGroup<Context>) {
        let admin = group.group("projects")

        admin.post(use: createProject)
        admin.get(use: listProjects)
        admin.get(":id", use: getProject)
        admin.delete(":id", use: deleteProject)
    }

  

    struct CreateProjectRequest: Decodable {
        let name: String
        let region: String
    }



    func createProject(_ request: Request, context: Context) async throws -> Client {
    let data = try await request.decode(as: CreateProjectRequest.self, context: context)

  
    let dbPassword = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    let client = try await fluent.db().withConnection { db -> Client in
        let c = Client(name: data.name, status: "creating")
        try await c.create(on: db)
        return c
    }

    let project = try await supabaseService.createProject(
        name: data.name,
        dbPass: dbPassword,
        organizationId: organizationId,
        region: data.region
    )

    try await fluent.db().withConnection { db in
        client.supabaseProjectId = project.id
        client.dbPassword = dbPassword
        try await client.update(on: db)
    }

       let keys = try await supabaseService.getProjectApiKeys(ref: project.id)

    if let anon = keys.first(where: { $0.name == "anon" }),
       let service = keys.first(where: { $0.name == "service_role" }) {
        try await fluent.db().withConnection { db in
            client.anonKey = anon.api_key
            client.serviceKey = service.api_key
            try await client.update(on: db)
        }
    }

        return client
    }


    func listProjects(_ request: Request, context: Context) async throws -> [Client] {
        return try await fluent.db().withConnection { db in
            try await Client.query(on: db).all()
        }
    }

    func getProject(_ request: Request, context: Context) async throws -> Client {
        guard let idString = context.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw HTTPError(.notFound)
        }

        let client = try await fluent.db().withConnection { db -> Client? in
            try await Client.find(id, on: db)
        }

        guard let client = client else {
            throw HTTPError(.notFound)
        }
        if let ref = client.supabaseProjectId {
            let status = try await supabaseService.checkProjectStatus(ref: ref)
            switch status {
            case .creating:
                client.status = "creating"
            case .provisioned:
                client.status = "provisioned"
            case .failed:
                client.status = "failed"
            }
        }

        return client
    }


func deleteProject(_ request: Request, context: Context) async throws -> String {
    guard let idString = context.parameters.get("id"),
          let id = UUID(uuidString: idString) else {
        throw HTTPError(.notFound)
    }

    guard let client = try await fluent.db().withConnection({ db in
        try await Client.find(id, on: db)
    }) else {
        throw HTTPError(.notFound)
    }

    if let ref = client.supabaseProjectId {
        do {
            _ = try await supabaseService.deleteProject(ref: ref)
        } catch let error as HTTPError where error.status == .notFound {
            fluent.logger.warning("Supabase project \(ref) already deleted, continuing")
        } catch {
            throw error
        }
    }

    try await fluent.db().withConnection { db in
        try await client.delete(on: db)
    }
    return "Project deleted successfully"
}


}
