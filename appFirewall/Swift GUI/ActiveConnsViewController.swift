//
//  ActiveConnsViewController.swift
//  appFirewall
//
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import Cocoa

class ActiveConnsViewController: appViewController {
    @IBOutlet weak var tableView: NSTableView?

    override func viewDidLoad() {
        // Do any additional setup after loading the view.
        super.viewDidLoad()
        appViewDidLoad(tableView: tableView, tab: 0, ascKey: "active_asc", sortKeys: ["pid", "domain"])
        start_pid_watcher() // start pid monitoring thread, its ok to call this multiple times
    }

    override func viewWillAppear() {
        // window is opening, populate it with content
        super.viewWillAppear()
        appViewWillAppear()
    }

    @objc override func refresh(timer: Timer?) {
        // might happen if timer fires before/after view is closed
        if !isViewLoaded { return }

        var force: Bool = false
        if timer == nil {
            force = true
        }
        guard let rect = tableView?.visibleRect else { print("WARNING: activeConns problem getting visible rectangle in refresh"); return }
        guard let firstVisibleRow = tableView?.rows(in: rect).location else { print("WARNING: activeConns problem getting first visible row in refresh"); return }
        if force || ((firstVisibleRow == 0) && (Int(get_pid_changed()) != 0)) {
            saveSelected() // save set of currently selected rows
            clear_pid_changed()
            update_gui_pid_list()
            tableView?.reloadData()
        }
    }

    override func numTableRows() -> Int {
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

            let item = get_connlist_item(get_blocklist(),Int32(0))
            let name = String(cString: get_connlist_item_name(item))
            let addr_name = String(cString: get_connlist_item_addrname(item))
            let domain = String(cString: get_connlist_item_domain(item))
            
            del_connitem(get_blocklist(), &self.bl_item_ref!)
            del_connitem(get_blocklist(), item)

            let size = Int(get_connlist_size(get_blocklist()))
            print("check size: \(size)")
            print("ASD")
            if size == 0 {
                self.flag = false
            }
        }
    }

    override func getTableCell(tableView: NSTableView, tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
            setColor(cell: cell, udp: Int(item.raw.udp) == 1, white: white, blocked: blocked)
            return cell
        }
    }
}
