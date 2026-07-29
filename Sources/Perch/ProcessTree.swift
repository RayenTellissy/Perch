import Darwin
import Foundation

// Walks the BSD process tree to find the controlling TTY and the GUI
// terminal application that owns a process.
enum ProcessTree {
    struct Info {
        let pid: pid_t
        let ppid: pid_t
        let ttyDevice: dev_t
    }

    static func info(for pid: pid_t) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var proc = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &proc, &size, nil, 0) == 0, size > 0 else { return nil }
        return Info(
            pid: pid,
            ppid: proc.kp_eproc.e_ppid,
            ttyDevice: proc.kp_eproc.e_tdev
        )
    }

    static func path(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func ancestors(of pid: pid_t) -> [pid_t] {
        var chain: [pid_t] = []
        var current = pid
        while current > 1, chain.count < 32 {
            chain.append(current)
            guard let info = info(for: current) else { break }
            current = info.ppid
        }
        return chain
    }

    static func ttyPath(startingFrom pid: pid_t) -> String? {
        for ancestor in ancestors(of: pid) {
            guard let info = info(for: ancestor), info.ttyDevice != dev_t(bitPattern: UInt32.max), info.ttyDevice != 0 else { continue }
            if let name = devname(info.ttyDevice, mode_t(S_IFCHR)) {
                return "/dev/" + String(cString: name)
            }
        }
        return nil
    }

    // First ancestor living inside a .app bundle, e.g. iTerm2, Ghostty, VS Code.
    // The hook process is the Perch binary itself and lives inside an
    // .app bundle too — never report it as the host
    static func terminalApp(startingFrom pid: pid_t) -> (pid: pid_t, path: String)? {
        for ancestor in ancestors(of: pid) {
            guard let path = path(for: ancestor) else { continue }
            if path.contains("Perch") { continue }
            if path.contains(".app/Contents/MacOS/") {
                return (ancestor, path)
            }
        }
        return nil
    }
}
