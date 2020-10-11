//
//  cHelpers.swift
//  appFirewall
//
//  Created by Doug Leith on 26/11/2019.
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import AppKit
import Foundation

// -------------------------------------
// C helpers

func setup_sig_handlers() {
    // if a C routine fatally fails it raises a SIGHUP signal
    // and we catch it here to raise an popup to inform user
    // and exit gracefully
    /* let handler: @convention(c) (Int32) -> () = { sig in
     	print("signal ",String(sig)," caught")
     	exit_popup(msg:String(cString: get_error_msg()), force:Int(get_error_force()))
     } */
    let backtrace_handler: @convention(c) (Int32) -> Void = { sig in
        // handle the signal

        // save backtrace, we'll catch this when restart (of course that's hoping we are not in such a bad state
        // that this fails e.g. we still need to have malloc functioning for Thread.callStackSymbols to work)
        // NB: to map from backtrace output so line number in source use atos. e.g. for the line "0 appFirewall 0x00000001000535ef " in backtrace "atos -o appFirewall.app/Contents/MacOS/appFirewall 0x00000001000535ef" returns "AppDelegate.applicationWillFinishLaunching(_:) (in appFirewall) (AppDelegate.swift:182)"
        UserDefaults.standard.set(Thread.callStackSymbols, forKey: "backtrace")
        UserDefaults.standard.set(sig, forKey: "signal")
        // print to log
        print("signal ", sig)
        Thread.callStackSymbols.forEach { print($0) }
        exit(1)
    }

    /* var action = sigaction(__sigaction_u:
     											unsafeBitCast(handler, to: __sigaction_u.self),
     											sa_mask: 0,
     											sa_flags: 0)
     sigaction(SIGUSR1, &action, nil) */

    // and dump backtrace on other fatal errors
    var action = sigaction(__sigaction_u: unsafeBitCast(backtrace_handler,
                                                        to: __sigaction_u.self),
                           sa_mask: 0,
                           sa_flags: 0)
    sigaction(SIGSEGV, &action, nil)
    sigaction(SIGABRT, &action, nil)
    sigaction(SIGIOT, &action, nil)
    sigaction(SIGBUS, &action, nil)
    sigaction(SIGFPE, &action, nil)
    sigaction(SIGILL, &action, nil)
}

// -------------------------------------
// C helpers
func make_data_dir() {
    // create Library/Application Support/appFirewall directory if
    // it doesn't already exist, and pass path on to C routines
    let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
    let appname = Bundle.main.infoDictionary!["CFBundleName"] as! String
    let path = paths[0] + "/" + appname
    if !FileManager.default.fileExists(atPath: path) {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            print("created " + path)
        } catch {
            print("problem making data_dir: " + error.localizedDescription)
        }
    }
    // and tell C helpers what the path we're using is
    set_path(path + "/")
    print("storage path " + path)
}

func save_state() {
    DispatchQueue.global(qos: .background).async {
        save_log(Config.logName)
        save_connlist(get_blocklist(), Config.blockListName); save_connlist(get_whitelist(), Config.whiteListName)
        save_dns_cache(Config.dnsName); save_dns_conn_list(Config.dnsConnListName)
    }
}

func load_state() {
    load_log(Config.logName, Config.logTxtName)
    load_connlist(get_blocklist(), Config.blockListName); load_connlist(get_whitelist(), Config.whiteListName)
    load_dns_cache(Config.dnsName)
    // we distribute app with preconfigured dns_conn cache so that
    // can guess process names of common apps more quickly
    let filePath = String(cString: get_path())
    let backupPath = Bundle.main.resourcePath ?? "./"
    if load_dns_conn_list(filePath, Config.dnsConnListName) < 0 {
        print("Falling back to loading dns_conn_list from ", backupPath)
        load_dns_conn_list(backupPath, Config.dnsConnListName)
    }
}

import Compression

func getSampleDir() -> String? {
    let sampleDir = String(cString: get_path()) + "samples/"
    if !FileManager.default.fileExists(atPath: sampleDir) {
        do {
            try FileManager.default.createDirectory(atPath: sampleDir, withIntermediateDirectories: true, attributes: nil)
            print("created " + sampleDir)
        } catch {
            print("WARNING: problem making sample dir: " + error.localizedDescription)
            return nil
        }
    }
    return sampleDir
}

func runCmd(cmd: String, args: [String]) -> String {
    let task = Process()
    task.launchPath = cmd
    task.arguments = args
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.launch()
    let resp = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    // resp is a Data object i.e. a bytebuffer
    // so convert to string
    let resp_str = (String(data: resp, encoding: .utf8) ?? "-1").trimmingCharacters(in: .whitespacesAndNewlines)
    return resp_str
}

func getFileXattribs(file: String) -> [String] {
    /*
     // this is nicer but doesn't return all of the extended attributes
     var names:[String] = []
     if let attr = try? FileManager.default.attributesOfItem(atPath:file) as NSDictionary {
     	if let xattribs = attr["NSFileExtendedAttributes"] as? NSDictionary {
     		for (key,_) in xattribs {
     			if let str = key as? String {
     				names.append(str)
     			}
     		}
     	}
     }
     return names*/

    let bufLength = listxattr(file, nil, 0, 0)
    if bufLength != -1 {
        let buf = UnsafeMutablePointer<Int8>.allocate(capacity: bufLength)
        if listxattr(file, buf, bufLength, 0) != -1 {
            if var names = NSString(bytes: buf, length: bufLength, encoding: String.Encoding.utf8.rawValue)?.components(separatedBy: "\0") {
                names.removeLast()
                return names
            }
        }
    }
    return []
}

func getIntstalledApps() -> [String] {
    // returns a list of app names from /Applications.  doesn't include
    // embedded apps e.g. Google Chrome Helper (which is embedded inside
    // Google Chrome and its metadata isn't tagged as an app)

    // to do ? could also use NSMetadataQuery but it seems much nastier
    let output = runCmd(cmd: "/usr/bin/mdfind", args: ["kMDItemContentTypeTree=com.apple.application-bundle", "-onlyin", "/Applications"])
    // print(output)
    var apps: [String] = []
    for item in output.components(separatedBy: "\n") {
        // if let b = Bundle(path: item) {
        // print(b.infoDictionary?["CFBundleName"], " ", p.lastPathComponent)
        // }
        if let p = Bundle(path: item)?.executableURL?.lastPathComponent {
            apps.append(p)
        }
    }
    return apps
}

func pgrep(Name: String) -> Int {
    // return whether any running processing match Name
    let res = Int(find_proc(Name))
    print("pgrep for ", Name, ": ", res)
    return res

    /* import AppKit
     let res = NSWorkspace.shared.runningApplications
     var count = 0
     for r in res {
     	print(r.localizedName," ",r.processIdentifier)
     	if (r.localizedName == Name) { print("match"); count += 1 }
     }
     print(count)
     return count */
}

func unitTesting() -> Bool {
    // return UserDefaults.standard.bool(forKey: "testing")
    return (NSClassFromString("XCTest") != nil)
    // return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

// MARK: - Handler UI

func restart_app() {
    // flag to app that its been restarted
    UserDefaults.standard.set(true, forKey: "restart")
    // relaunch app
    NSWorkspace.shared.launchApplication("appFirewall")
    /* let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
     let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
     let task = Process()
     task.launchPath = "/usr/bin/open"
     task.arguments = [path]
     task.launch() */

    // and stop our copy of app
    DispatchQueue.main.async {
        NSApp.terminate(nil) // tidy shutdown, calls applicationWillTerminate()
    }
}

func error_popup(msg: String) {
    print(msg) // print error to log
    let alert = NSAlert()
    alert.messageText = "Error"
    alert.informativeText = msg
    alert.alertStyle = .critical
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

func quiet_error_popup(msg: String, quiet: Bool) {
    if !quiet {
        DispatchQueue.main.async {
            error_popup(msg: msg)
        }
    } else { // if quiet, just print error to log
        print(msg)
    }
}
