//
//  configData.swift
//  appFirewall
//
//  Created by Doug Leith on 04/12/2019.
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import AppKit
import Foundation
import ServiceManagement

class Config: NSObject {
    // fixed settings ...
    static let defaultLoggingLevel = 2 // more verbose, for testing

    static let minHelperVersion = 15 // required helper version, must be an Int

    // ???
    static let csrutil = "/usr/bin/csrutil"
    static let pgrep = "/usr/bin/pgrep"

    static let logName = "log.dat"
    static let logTxtName = "log.txt" // human readable log file
    static let appLogName = "app_log.txt"
    static let dnsName = "dns.dat"
    static let blockListName = "blocklist.dat"
    static let whiteListName = "whitelist.dat"
    static let dnsConnListName = "dns_connlist.dat"

    static let appDelegateRefreshTime: Double = 10 // check state every 10s
    static let viewRefreshTime: Double = 1 // check for window update every 1s

    // ------------------------------------------------
    // settings that can be changed by user ...
    static var EnabledLists: [String] = []
    static var AvailableLists: [String] = []

    static func checkBlockQUIC_status() {
        // confirm actual firewall status matches our settings
        let blocked = QUIC_status()
        if (blocked == 1) && (!getBlockQUIC()) {
            print("WARNING: QUIC blocked when it should be unblocked")
            blockQUIC(value: true)
        } else if (blocked == 0) && getBlockQUIC() {
            print("WARNING: QUIC not blocked when it should be.")
            blockQUIC(value: false)
        }
    }

    static func initBlockQUIC() {
        if getBlockQUIC() == false {
            if let msg_ptr = unblock_QUIC() {
                print("WARNING: Problem trying to unblock QUIC")
                let helper_msg = String(cString: msg_ptr)
                let msg = "Problem trying to unblock QUIC (" + helper_msg + ")"
                DispatchQueue.main.async { error_popup(msg: msg) }
                // should we blockQUIC(value:true) since it might still be enabled ?
            }
        } else {
            if let msg_ptr = block_QUIC() {
                print("WARNING: Problem trying to block QUIC")
                let helper_msg = String(cString: msg_ptr)
                let msg = "Problem trying to block QUIC (" + helper_msg + ")"
                DispatchQueue.main.async { error_popup(msg: msg) }
                blockQUIC(value: false)
            }
        }
        checkBlockQUIC_status()
    }

    static func initLoad() {
        // called by app delegate at startup
        DispatchQueue.global(qos: .background).async {
            initBlockQUIC()
        }
    }

    enum options {
        case runAtLogin, blockQUIC
    }

    static func refresh(opts: Set<options>) {
        // run after updating config
        if opts.contains(.blockQUIC) { initBlockQUIC() }
    }

    static func runAtLogin(value: Bool) {
        UserDefaults.standard.set(value, forKey: "runAtLogin")
    }

    static func blockQUIC(value: Bool) {
        UserDefaults.standard.set(value, forKey: "blockQUIC")
    }

    static func getSetting(label: String, def: Bool) -> Bool {
        UserDefaults.standard.register(defaults: [label: def])
        return UserDefaults.standard.bool(forKey: label)
    }

    static func getRunAtLogin() -> Bool {
        return getSetting(label: "runAtLogin", def: false)
    }

    static func getBlockQUIC() -> Bool {
        return getSetting(label: "blockQUIC", def: false)
    }

    static func getDnscrypt_proxy() -> Bool {
        return getSetting(label: "dnscrypt_proxy", def: false)
    }
}
