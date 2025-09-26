import FluentPostgresDriver
import Hummingbird
import HummingbirdFluent
import Logging
import Foundation


public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var logLevel: Logger.Level? { get }
    var migrate: Bool { get }
    var revert: Bool { get }
}

typealias AppRequestContext = BasicRequestContext

public func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {

    loadDotEnv()

    var logger = Logger(label: "client-provision-api")
    if let level = arguments.logLevel {
        logger.logLevel = level
    }

    let fluent = Fluent(logger: logger)

    guard let dbURL = ProcessInfo.processInfo.environment["CONTROL_DB_URL"], !dbURL.isEmpty else {
        logger.critical("CONTROL_DB_URL not set in environment")
        fatalError("CONTROL_DB_URL not set")
    }

    guard let urlComponents = URLComponents(string: dbURL),
          let host: String = urlComponents.host,
          let user: String = urlComponents.user,
          let password = urlComponents.password,
          let dbName = urlComponents.path.split(separator: "/").first
    else {
        fatalError("CONTROL_DB_URL is invalid")
    }

    let port = urlComponents.port ?? 5432

    fluent.databases.use(
        .postgres(
            configuration: .init(
                hostname: host,
                port: port,
                username: user,
                password: password,
                database: String(dbName),
                tls: .disable 
            ),
            maxConnectionsPerEventLoop: 10
        ),
        as: .psql
    )
    logger.info("Connected to Supabase control DB (API pool, 20 connections)")

 
    let workerFluent = Fluent(logger: logger)
    workerFluent.databases.use(
        .postgres(
            configuration: .init(
                hostname: host,
                port: port,
                username: user,
                password: password,
                database: String(dbName),
                tls: .disable
            ),
            maxConnectionsPerEventLoop: 5
        ),
        as: .psql
    )
    logger.info("Worker DB pool ready (5 connections)")

    // --- Add Migrations ---
    await fluent.migrations.add(CreateClient())

    if arguments.migrate {
        do {
            try await fluent.migrate()
            logger.info("Migrations completed successfully")
        } catch {
            logger.error("Migration failed: \(String(reflecting: error))")
        }
    }

    if arguments.revert {
        do {
            try await fluent.revert()
            logger.info("Migrations reverted successfully")
        } catch {
            logger.error("Migration revert failed: \(String(reflecting: error))")
        }
    }

    // --- Supabase Service ---
    guard let supabaseKey = ProcessInfo.processInfo.environment["SUPABASE_MANAGEMENT_API_KEY"],
          !supabaseKey.isEmpty else {
        fatalError("SUPABASE_MANAGEMENT_API_KEY not set in environment")
    }
    let supabaseService = SupabaseService(apiKey: supabaseKey, logger: logger)

    // --- Organization ID ---
    guard let supabaseOrgId = ProcessInfo.processInfo.environment["SUPABASE_ORGANIZATION_ID"],
          !supabaseOrgId.isEmpty else {
        fatalError("SUPABASE_ORGANIZATION_ID not set in environment")
    }

    // --- Router ---
    let router = Router(context: AppRequestContext.self)
    router.add(middleware: LogRequestsMiddleware(arguments.logLevel ?? .info))

    // Health check
    router.get("/health") { _, _ in HTTPResponse.Status.ok }

    // --- Admin Controller ---
    let adminController = AdminController(
        fluent: fluent,
        supabaseService: supabaseService,
        organizationId: supabaseOrgId
    )
    adminController.addRoutes(to: router.group())

    // --- Application ---
    var app = Application(
        router: router,
        configuration: .init(address: .hostname(arguments.hostname, port: arguments.port)),
        logger: logger
    )
 
    app.addServices(fluent)
    app.addServices(
        ProjectPollingWorker(
            app: app,
            fluent: workerFluent,
            supabaseService: supabaseService,
            shortInterval: .seconds(30),  
            longInterval: .seconds(100)  
        )
    )

    return app
}
