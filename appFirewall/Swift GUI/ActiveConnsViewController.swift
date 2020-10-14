//
//  ActiveConnsViewController.swift
//  appFirewall
//
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import Cocoa

extension ActiveConnsViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return numTableRows()
    }
}

extension ActiveConnsViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return getTableCell(tableView: tableView, tableColumn: tableColumn, row: row)
    }
}

class ActiveConnsViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    var timer: Timer = Timer()
    var popover = NSPopover()
    var popoverRow: Int = -1

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.dataSource = self
        tableView.delegate = self

        start_pid_watcher()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        view.window?.setFrameUsingName("connsView")
        // record active tab

        // MARK: - RESRESHING of connections list every 1s

        timer = Timer.scheduledTimer(timeInterval: Config.viewRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
        refresh(timer: nil)
    }

    override func viewWillDisappear() {
        view.window?.saveFrame(usingName: "connsView") // record size of window
        timer.invalidate()

        super.viewWillDisappear()
    }

    @objc func refresh(timer: Timer?) {
        // might happen if timer fires before/after view is closed
        if !isViewLoaded { return }

        var force: Bool = false
        if timer == nil {
            force = true
        }
        guard let rect = tableView?.visibleRect else { print("WARNING: activeConns problem getting visible rectangle in refresh"); return }
        guard let firstVisibleRow = tableView?.rows(in: rect).location else { print("WARNING: activeConns problem getting first visible row in refresh"); return }
        if force || ((firstVisibleRow == 0) && (Int(get_pid_changed()) != 0)) {
            clear_pid_changed()
            update_gui_pid_list()
            tableView?.reloadData()
        }
    }

    func numTableRows() -> Int {
        return Int(get_num_gui_conns())
    }

    var bl_item_ref: bl_item_t?
    var flag = false

    @objc func buttonClick(_ sender: blButton?) {
        sender?.clickButton()
        bl_item_ref = sender?.bl_item

        guard flag == false else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.flag = true

            let item = get_connlist_item(get_blocklist(), Int32(0))
            let name = String(cString: get_connlist_item_name(item))
            let addr_name = String(cString: get_connlist_item_addrname(item))
            let domain = String(cString: get_connlist_item_domain(item))

            del_connitem(get_blocklist(), item)

            let size = Int(get_connlist_size(get_blocklist()))
            print("check size: \(size)")
            print("ASD")
            if size == 0 {
                self.flag = false
            }
        }
    }

    func getTableCell(tableView: NSTableView, tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // decide on table contents at specified col and row
        let r = mapRow(row: row)
        var item = get_gui_conn(Int32(r))
        var bl_item = conn_to_bl_item(&item)
        let blocked = Int(blocked_status(&bl_item))
        let white = Int(is_white(&bl_item))
        let c_ptr = conn_hash(&item)
        let hashStr = String(cString: c_ptr!)
        free(c_ptr)
        let ip = String(cString: &item.dst_addr_name.0)
        let src = String(cString: &item.src_addr_name.0)
        var domain = String(cString: &bl_item.domain.0)
        if domain.count == 0 { domain = ip }

        var cellIdentifier: String = ""
        var content: String = ""
        var tip: String
        if tableColumn == tableView.tableColumns[0] {
            tip = "PID: " + String(Int(item.pid))
        } else {
            var blocked_log = blocked
            if white == 1 { blocked_log = 0 }
            let ppp = is_ppp(item.raw.af, &item.raw.src_addr, &item.raw.dst_addr)
            tip = getTip(srcIP: src, ppp: ppp, ip: ip, domain: domain, name: String(cString: &bl_item.name.0), port: String(Int(item.raw.dport)), blocked_log: blocked_log, domains: String(cString: get_dns_count_str(item.raw.af, item.raw.dst_addr)))
        }

        if tableColumn == tableView.tableColumns[0] {
            cellIdentifier = "ProcessCell"
            content = String(cString: &item.name.0)
        } else if tableColumn == tableView.tableColumns[1] {
            cellIdentifier = "ConnCell"
            content = domain
            if Int(item.raw.udp) == 1 {
                if (item.raw.dport == 443) || (item.raw.dport == 80) {
                    content = content + " (UDP/QUIC)"
                } else if item.raw.dport == 53 {
                    content = content + " (UDP/DNS)"
                } else {
                    content = content + " (UDP/Port " + String(item.raw.dport) + ")"
                }
            }
        } else if tableColumn == tableView.tableColumns[2] {
            cellIdentifier = "ButtonCell"
        }

        let cellId = NSUserInterfaceItemIdentifier(rawValue: cellIdentifier)
        if cellIdentifier == "ButtonCell" {
            guard let cell = tableView.makeView(withIdentifier: cellId, owner: self) as? blButton else { print("WARNING: problem in activeConns getting button cell"); return nil }
            cell.udp = (Int(item.raw.udp) > 0)
            cell.bl_item = bl_item // take a copy so ok to free() later
            cell.tip = tip
            cell.hashStr = hashStr
//             restore selected state of this row
//            restoreSelected(row: row, hashStr: cell.hashStr)
            // set tool tip and title;
            cell.updateButton()
            cell.action = #selector(buttonClick(_:))
            return cell
        } else {
            guard let cell = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView else { print("WARNING: problem in activeConns getting non-button cell"); return nil }
            cell.textField?.stringValue = content
            cell.textField?.toolTip = tip

            return cell
        }
    }
}

// MARK: - Shit??

extension ActiveConnsViewController {
    func getRowText(row: Int) -> String {
        guard let cell0 = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView else { return "" }
        guard let str0 = cell0.textField?.stringValue else { return "" }
        guard let cell1 = tableView.view(atColumn: 1, row: row, makeIfNecessary: true) as? NSTableCellView else { return "" }
        let str1 = cell1.textField?.stringValue ?? ""
        let tip = cell1.textField?.toolTip ?? ""
        return str0 + " " + str1 + " [" + tip + "]\n"
    }
    
    @objc func updateTable(rowView: NSTableRowView, row: Int) {
        // update all of the buttons in table (called after
        // pressing a button changes blacklist state etc)
        guard let cell2 = rowView.view(atColumn: 2) as? blButton else { print("WARNING: problem in updateTable getting cell 2 for row ", row); return }
        cell2.updateButton()
    }
    
    func mapRow(row: Int) -> Int {
        // map from displayed row to row in list itself
        let log_last = numTableRows() - 1
        if row < 0 { return 0 }
        if row > log_last { return log_last }

        return row
    }

    func invMapRow(r: Int) -> Int {
        // map from row in list to displayed row
        let log_last = numTableRows() - 1
        if r < 0 { return 0 }
        if r > log_last { return log_last }

        return r
    }


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
