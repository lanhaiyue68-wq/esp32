import Foundation

/// Only app-owned diagnostic files; preferences, calibration and task data are outside this scope.
struct DiagnosticFiles {
    struct Policy {
        var maxRuns = 20
        var maxAge: TimeInterval = 7 * 86400
        var maxBytes = 80 * 1024 * 1024
        var videoBytes = 8 * 1024 * 1024
        var videoFrames = 120
        var imageBytes = 12 * 1024 * 1024
        var exportBytes = 20 * 1024 * 1024
    }
    struct Usage { var bytes = 0; var runs = 0 }
    let documents: URL
    let temporary: URL
    var policy = Policy()
    var root: URL { documents.appendingPathComponent("traces") }
    func usage() -> Usage { Usage() }
    @discardableResult func maintain(active: URL? = nil, now: Date = Date()) throws -> Usage { usage() }
    func clear(active: URL? = nil) throws {}
    func exportStage() throws -> URL { temporary.appendingPathComponent("diagnostic-export") }
}
