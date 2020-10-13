//
//  MainViewModel.swift
//  MacLogout
//
//  Created by Sergey Fominov on 10/13/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

import Foundation

class MainViewModel: ObservableObject {
    @Published var selectedAccentIndex: Int?
    var timer: Timer = Timer()

    var bl_item: bl_item_t?

    init() {
        start_pid_watcher() // start pid monitoring thread, its ok to call this multiple times

        self.timer = Timer.scheduledTimer(timeInterval: Config.viewRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
        refresh(timer: nil)
    }

    @objc func refresh(timer: Timer?) {
        guard Int(get_pid_changed()) != 0 else {
            return
        }

        clear_pid_changed()
        update_gui_pid_list()
        numTableRows()
    }

    var numRows: Int = 0

    func numTableRows() {
        numRows = Int(get_num_gui_conns())
        let value = Int(get_num_gui_conns())
        if value == 0 {
            return
        }
        for i in 0...value {
            print(i)
            let model = show(row: i)
        }

        print("------------------------------------------------------")
    }

    var bl_item_ref: bl_item_t?

    func findAndBlockPoe() {
        var bl_item = bl_item_ref!

        let blocked2 = Int(blocked_status(&bl_item))
        let white1 = Int(is_white(&bl_item))

        print("blocked: \(blocked2), white: \(white1)")

        let name = String(cString: &bl_item.name.0)
        if (name.count == 0) || name.contains(NOTFOUND) {
            print("Tried to block item with process name ", NOTFOUND, " or ''")
            return // PID name is missing, we can't add this to block list
        }

        let domain = String(cString: &bl_item.domain.0)
        var white: Int = 0
        if in_connlist_htab(get_whitelist(), &bl_item, 0) != nil {
            white = 1
        }
        var blocked: Int = 0
        if in_connlist_htab(get_blocklist(), &bl_item, 0) != nil {
            blocked = 1
        } else if in_hostlist_htab(domain) != nil {
            blocked = 2
        } else if in_blocklists_htab(&bl_item) != nil {
            blocked = 3
        }

        print("ASD")
//        del_connitem(get_blocklist(), &bl_item)
        let size = Int(get_connlist_size(get_blocklist()))

        print("check size: \(size)")
        if isBlocking == false {
            if blocked == 1 { // on block list, remove
                del_connitem(get_blocklist(), &bl_item)
            } else if blocked > 1 { // on host list, add to whitelist
                add_connitem(get_whitelist(), &bl_item)
            }
            isBlocking = true
        } else { // block
            if white == 1 { // on white list, remove
                del_connitem(get_whitelist(), &bl_item)
            }
            if blocked == 0 {
                add_connitem(get_blocklist(), &bl_item)
            }
            isBlocking = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
            let item = get_connlist_item(get_blocklist(), Int32(0))
            del_connitem(get_blocklist(), item)

            let size = Int(get_connlist_size(get_blocklist()))
            print("check size: \(size)")
            print("THE END")
//            self.tryToBlock(bl_item: &kek!.blItem)
        }
    }

    func mapRow(row: Int) -> Int {
        // map from displayed row to row in list itself
        let log_last = numRows - 1
        if row < 0 { return 0 }
        if row > log_last { return log_last }

        return row
    }

    func show(row: Int) {
        let kek = mapRow(row: row)
        var item = get_gui_conn(Int32(kek))
        var bl_item = conn_to_bl_item(&item)

        let blocked = Int(blocked_status(&bl_item))
        let white = Int(is_white(&bl_item))
        let c_ptr = conn_hash(&item)
        let hashStr = String(cString: c_ptr!)
        free(c_ptr)

        let ip = String(cString: &item.dst_addr_name.0)
        let src = String(cString: &item.src_addr_name.0)
        var domain = String(cString: &bl_item.domain.0)

        if domain.count == 0 {
            domain = ip
        }

        let content = String(cString: &item.name.0)

        var tip: String
        var blocked_log = blocked
        if white == 1 { blocked_log = 0 }
        let ppp = is_ppp(item.raw.af, &item.raw.src_addr, &item.raw.dst_addr)
        tip = getTip(srcIP: src, ppp: ppp, ip: ip, domain: domain, name: String(cString: &bl_item.name.0), port: String(Int(item.raw.dport)), blocked_log: blocked_log, domains: String(cString: get_dns_count_str(item.raw.af, item.raw.dst_addr)))
        

        if content.contains("Exile") {
            print("IM FOUND POE: \(content), \(domain), bl item: \(bl_item)")
            print("TIP: \(tip)")
            bl_item_ref = bl_item
        }
    }

    var isBlocking = false

    func tryToBlock(bl_item: inout bl_item_t) {
        let name = String(cString: &bl_item.name.0)
        if (name.count == 0) || name.contains(NOTFOUND) {
            print("Tried to block item with process name ", NOTFOUND, " or ''")
            return // PID name is missing, we can't add this to block list
        }

        let domain = String(cString: &bl_item.domain.0)
        var white: Int = 0
        if in_connlist_htab(get_whitelist(), &bl_item, 0) != nil {
            white = 1
        }
        var blocked: Int = 0
        if in_connlist_htab(get_blocklist(), &bl_item, 0) != nil {
            blocked = 1
        } else if in_hostlist_htab(domain) != nil {
            blocked = 2
        } else if in_blocklists_htab(&bl_item) != nil {
            blocked = 3
        }

        if isBlocking == false {
            if blocked == 1 { // on block list, remove
                del_connitem(get_blocklist(), &bl_item)
            } else if blocked > 1 { // on host list, add to whitelist
                add_connitem(get_whitelist(), &bl_item)
            }
        } else { // block
            if white == 1 { // on white list, remove
                del_connitem(get_whitelist(), &bl_item)
            }
            if blocked == 0 {
                add_connitem(get_blocklist(), &bl_item)
            }
        }
    }
}

extension MainViewModel {
    func getTip(srcIP: String = "", ppp: Int32 = 0, ip: String, domain: String, name: String, port: String, blocked_log: Int, domains: String) -> String {
        var tip: String = ""
        var domain_ = domain
        if domain.count == 0 {
            domain_ = ip
        }
        var maybe = "blocked"
        var vpn: String = ""
        if ppp > 0 {
            maybe = "marked as blocked"
            vpn = "NB: Filtering of VPN connections is currently unreliable.\n"
        } else if ppp < 0 {
            maybe = "marked as blocked"
            vpn = "Zombie connection: interface has gone away, but app hasn't noticed yet.\n"
        }
        var dns = ""
        if (Int(port) == 53) && (name != "dnscrypt-proxy") {
            dns = "Its a good idea to encrypt DNS traffic by enabling DNS-over-HTTPS in the appFirewall preferences."
        }
        if blocked_log == 0 {
            tip = "This connection to " + domain_ + " (" + ip + ":" + port + ") was not blocked. " + dns
        } else if blocked_log == 1 {
            tip = "This connection to " + domain_ + " (" + ip + ":" + port + ") was " + maybe + " for application '" + name + "' by user black list. " + dns + vpn
        } else if blocked_log == 2 {
            tip = "This connection to " + domain_ + " (" + ip + ":" + port + ") was " + maybe + " for all applications by hosts file. " + dns + vpn
        } else {
            tip = "This connection to " + domain_ + " (" + ip + ":" + port + ") was " + maybe + " for application '" + name + "' by hosts file. " + dns + vpn
        }
        // add some info on whether IP is shared by multiple domains
        tip += "Domains associated with this IP address: " + domains
        return tip
    }
}
