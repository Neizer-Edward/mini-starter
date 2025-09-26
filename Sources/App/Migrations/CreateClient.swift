import FluentKit

struct CreateClient: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("clients")
            .id()
            .field("name", .string, .required)
            .field("supabase_project_id", .string)
            .field("db_password", .string)
            .field("db_connection", .string)
            .field("status", .string, .required)
            .field("anon_key", .string)
            .field("service_key", .string)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("clients").delete()
    }
}
