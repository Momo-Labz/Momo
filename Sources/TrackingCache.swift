import Foundation
import SQLite3

actor TrackingCache {
    static let acceptedObservationFreshness: TimeInterval = 15 * 60

    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL = TrackingCache.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    @discardableResult
    func accept(_ observation: ProviderUsageObservation, now: Date = .now) -> Bool {
        guard observation.isFresh(at: now), let database = openDatabase() else { return false }
        removeExpired(now: now)
        let sql = """
        INSERT INTO usage_observations
            (provider, metric, percentage, resets_at, captured_at, freshness, provenance)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        ON CONFLICT(provider, metric) DO UPDATE SET
            percentage=excluded.percentage,
            resets_at=excluded.resets_at,
            captured_at=excluded.captured_at,
            freshness=excluded.freshness,
            provenance=excluded.provenance
        WHERE excluded.captured_at >= usage_observations.captured_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bind(observation.provider.rawValue, at: 1, to: statement)
        bind(observation.metric, at: 2, to: statement)
        if let percentage = observation.percentage { sqlite3_bind_int(statement, 3, Int32(percentage)) }
        else { sqlite3_bind_null(statement, 3) }
        if let resetsAt = observation.resetsAt { sqlite3_bind_double(statement, 4, resetsAt.timeIntervalSince1970) }
        else { sqlite3_bind_null(statement, 4) }
        sqlite3_bind_double(statement, 5, observation.capturedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, observation.freshness)
        bind(observation.provenance.rawValue, at: 7, to: statement)
        return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) > 0
    }

    @discardableResult
    func accept(_ incoming: [ProviderUsageObservation], now: Date = .now) -> Int {
        incoming.reduce(into: 0) { count, observation in
            if accept(observation, now: now) { count += 1 }
        }
    }

    func observations(for provider: AIProvider? = nil, now: Date = .now) -> [ProviderUsageObservation] {
        guard let database = openDatabase() else { return [] }
        removeExpired(now: now)
        let sql = provider == nil
            ? "SELECT provider, metric, percentage, resets_at, captured_at, freshness, provenance FROM usage_observations ORDER BY provider, metric COLLATE NOCASE"
            : "SELECT provider, metric, percentage, resets_at, captured_at, freshness, provenance FROM usage_observations WHERE provider = ?1 ORDER BY metric COLLATE NOCASE"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        if let provider { bind(provider.rawValue, at: 1, to: statement) }
        var result: [ProviderUsageObservation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let providerText = text(at: 0, from: statement),
                  let decodedProvider = AIProvider(rawValue: providerText),
                  let metric = text(at: 1, from: statement),
                  let provenanceText = text(at: 6, from: statement),
                  let provenance = UsageProvenance(rawValue: provenanceText) else { continue }
            let percentage = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(statement, 2))
            let resetsAt = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            result.append(ProviderUsageObservation(
                provider: decodedProvider,
                metric: metric,
                percentage: percentage,
                resetsAt: resetsAt,
                capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                freshness: sqlite3_column_double(statement, 5),
                provenance: provenance
            ))
        }
        return result
    }

    func removeAll() {
        guard let database = openDatabase() else { return }
        sqlite3_exec(database, "DELETE FROM usage_observations", nil, nil, nil)
    }

    static var defaultDatabaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MOMO", isDirectory: true)
            .appendingPathComponent("tracking-cache.sqlite3")
    }

    private func openDatabase() -> OpaquePointer? {
        if let database { return database }
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        let schema = """
        CREATE TABLE IF NOT EXISTS usage_observations (
            provider TEXT NOT NULL,
            metric TEXT NOT NULL COLLATE NOCASE,
            percentage INTEGER,
            resets_at REAL,
            captured_at REAL NOT NULL,
            freshness REAL NOT NULL,
            provenance TEXT NOT NULL,
            PRIMARY KEY (provider, metric)
        );
        CREATE INDEX IF NOT EXISTS usage_observations_provider_captured
            ON usage_observations(provider, captured_at DESC);
        CREATE INDEX IF NOT EXISTS usage_observations_freshness
            ON usage_observations(captured_at, freshness);
        """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        database = handle
        return handle
    }

    private func removeExpired(now: Date) {
        guard let database = openDatabase() else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "DELETE FROM usage_observations WHERE captured_at > ?1 OR captured_at + freshness < ?1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func text(at index: Int32, from statement: OpaquePointer) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }
}
