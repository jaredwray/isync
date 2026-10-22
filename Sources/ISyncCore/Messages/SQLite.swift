import Foundation

#if canImport(SQLite3)
    import SQLite3
#else
    import CSQLite
#endif

/// An error from SQLite. The message comes from `sqlite3_errmsg` and holds no row data.
struct SQLiteError: Error, CustomStringConvertible, Sendable {
    let code: Int32
    let message: String

    var description: String { "SQLite error \(code): \(message)" }
}

/// One SQLite connection. Use a connection on one thread only.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(path: String, readOnly: Bool) throws {
        var connection: OpaquePointer?
        let access = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let code = sqlite3_open_v2(path, &connection, access | SQLITE_OPEN_NOMUTEX, nil)
        guard code == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot allocate a connection"
            sqlite3_close(connection)
            throw SQLiteError(code: code, message: message)
        }
        handle = connection
        // Messages.app writes to chat.db while the sync reads it.
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw lastError(code) }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw lastError(code) }
        return SQLiteStatement(handle: statement, database: self)
    }

    /// The column names of `table`, or an empty set if the table does not exist.
    func columnNames(of table: String) throws -> Set<String> {
        let statement = try prepare("SELECT name FROM pragma_table_info(?1)")
        try statement.bind(text: table, at: 1)
        var names = Set<String>()
        while try statement.step() {
            if let name = statement.string(at: 0) { names.insert(name) }
        }
        return names
    }

    fileprivate func lastError(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }
}

/// One prepared statement. It keeps its connection open.
final class SQLiteStatement {
    private let handle: OpaquePointer
    private let database: SQLiteDatabase

    fileprivate init(handle: OpaquePointer, database: SQLiteDatabase) {
        self.handle = handle
        self.database = database
    }

    deinit {
        sqlite3_finalize(handle)
    }

    /// Binds 64-bit integers to the parameters 1...n.
    func bind(_ values: [Int64]) throws {
        for (offset, value) in values.enumerated() {
            let code = sqlite3_bind_int64(handle, Int32(offset + 1), value)
            guard code == SQLITE_OK else { throw database.lastError(code) }
        }
    }

    func bind(text: String, at index: Int32) throws {
        // SQLITE_TRANSIENT tells SQLite to copy the bytes before the call returns.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let code = sqlite3_bind_text(handle, index, text, -1, transient)
        guard code == SQLITE_OK else { throw database.lastError(code) }
    }

    /// Moves to the next row. Returns false after the last row.
    func step() throws -> Bool {
        let code = sqlite3_step(handle)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw database.lastError(code)
        }
    }

    func isNull(at column: Int32) -> Bool {
        sqlite3_column_type(handle, column) == SQLITE_NULL
    }

    func int64(at column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    func optionalInt64(at column: Int32) -> Int64? {
        isNull(at: column) ? nil : int64(at: column)
    }

    func string(at column: Int32) -> String? {
        guard !isNull(at: column), let pointer = sqlite3_column_text(handle, column) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
    }

    func data(at column: Int32) -> Data? {
        guard !isNull(at: column) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        guard count > 0, let pointer = sqlite3_column_blob(handle, column) else { return Data() }
        return Data(bytes: pointer, count: count)
    }
}
