import FluentKit
import Foundation
import Hummingbird

final class Client: @unchecked Sendable, Model, ResponseCodable {
    static let schema = "clients"

    @ID(custom: "id", generatedBy: .user)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "supabase_project_id")
    var supabaseProjectId: String?

    @OptionalField(key: "db_password")
    var dbPassword: String?

    @OptionalField(key: "db_connection")
    var dbConnection: String?

    @OptionalField(key: "anon_key")
    var anonKey: String?

    @OptionalField(key: "service_key")
    var serviceKey: String?

    @Field(key: "status")
    var status: String

    init() {}

    init(id: UUID = UUID(), name: String, status: String = "requested") {
        self.id = id
        self.name = name
        self.status = status
    }
}

