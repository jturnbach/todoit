import Foundation

public enum AppPaths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = base.appendingPathComponent("TodoIt", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    public static var tasksFile: URL {
        supportDirectory.appendingPathComponent("tasks.json")
    }

    public static var lockFile: URL {
        supportDirectory.appendingPathComponent("tasks.lock")
    }
}
