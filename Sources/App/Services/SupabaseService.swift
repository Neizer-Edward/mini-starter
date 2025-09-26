import Foundation
import FoundationNetworking 
import Hummingbird
import Logging

struct SupabaseService {
    let apiKey: String
    let logger: Logger
    let baseURL: String = "https://api.supabase.com/v1"

    struct CreateProjectRequest: Codable {
        let db_pass: String
        let name: String
        let organization_id: String
        let region: String
        let plan: String? 
        let desired_instance_size: String? 
    }

    struct ProjectResponse: Codable {
        let id: String
        let organization_id: String
        let name: String
        let region: String
        let created_at: String
        let status: String
        let database: DatabaseInfo?

        struct DatabaseInfo: Codable {
            let host: String?
            let version: String?
            let postgres_engine: String?
            let release_channel: String?
        }
    }

    struct DeleteProjectResponse: Codable {
        let id: Int
        let ref: String
        let name: String
    }

    enum ProjectStatus {
        case creating
        case provisioned(dbHost: String)
        case failed
    }

    func createProject(
        name: String,
        dbPass: String,
        organizationId: String,
        region: String
    ) async throws -> ProjectResponse {
        let url = URL(string: "\(baseURL)/projects")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateProjectRequest(
            db_pass: dbPass,
            name: name,
            organization_id: organizationId,
            region: region,
            plan: nil,
            desired_instance_size: nil
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HTTPError(.badRequest, message: "Failed to create project: \(errorBody)")
        }

        return try JSONDecoder().decode(ProjectResponse.self, from: data)
    }

    func getProject(ref: String) async throws -> ProjectResponse {
        let url = URL(string: "\(baseURL)/projects/\(ref)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HTTPError(.badRequest, message: "Failed to get project: \(errorBody)")
        }
        return try JSONDecoder().decode(ProjectResponse.self, from: data)
    }

    func deleteProject(ref: String) async throws -> DeleteProjectResponse {
        let url = URL(string: "\(baseURL)/projects/\(ref)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HTTPError(.badRequest, message: "Failed to delete project: \(errorBody)")
        }

        return try JSONDecoder().decode(DeleteProjectResponse.self, from: data)
    }

    enum ProjectStatusResponse: String, Codable {
    case active
    case inactive
    case comingUp
    case restoring
    case upgrading
    case pausing
    case paused
    case restarting
    case resizing
    case goingDown
    case unknown
    case activeHealthy
    case activeUnhealthy
    case initFailed
    case restoreFailed
    case pauseFailed
    case removed
    
    private enum CodingKeys: String, CodingKey {
        case active
        case inactive
        case comingUp
        case restoring
        case upgrading
        case pausing
        case paused
        case restarting
        case resizing
        case goingDown = "going_down"
        case unknown
        case activeHealthy = "active_healthy"
        case activeUnhealthy = "active_unhealthy"
        case initFailed = "init_failed"
        case restoreFailed = "restore_failed"
        case pauseFailed = "pause_failed"
        case removed
    }

    }



    func checkProjectStatus(ref: String) async throws -> ProjectStatus {
        let project = try await getProject(ref: ref)

        guard let status = ProjectStatusResponse(rawValue:project.status.lowercased()) else {
            return .failed
        }

        switch status {

        case .inactive, .comingUp, .restoring, .upgrading, .pausing,
                .paused, .restarting, .resizing, .goingDown, .unknown:
            return .creating

        case .activeHealthy:
            if let host = project.database?.host {
                return .provisioned(dbHost: host)
            } else {
                return .creating
            }

        case .activeUnhealthy:
            if let host = project.database?.host {
                logger.warning(" Supabase project \(project.id) is ACTIVE but unhealthy")
                return .provisioned(dbHost: host)
            } else {
                return .creating
            }

        case .initFailed, .restoreFailed, .pauseFailed:
            return .failed

        case  .removed:
            return .failed

        default:
            return .creating
            }
        }

    }


    extension SupabaseService {
        struct SupabaseApiKey: Decodable {
            let api_key: String
            let name: String
        }

    func getProjectApiKeys(ref: String) async throws -> [SupabaseApiKey] {
        let url = URL(string: "\(baseURL)/projects/\(ref)/api-keys")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw HTTPError(.badRequest, message: "Failed to get project API keys: \(errorBody)")
        }

        return try JSONDecoder().decode([SupabaseApiKey].self, from: data)
    }
}

