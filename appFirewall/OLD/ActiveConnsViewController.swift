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
            
            numLol()
        }
    }
    
    func numLol() {
        let value = numTableRows()
        guard value > 0 else {
            return
        }
        
        for i in 0...value {
            catchPoePid(row: i)
        }
    }
    
    func catchPoePid(row: Int) {
        let r = mapRow(row: row)
        var item = get_gui_conn(Int32(r))
        
        let name = String(cString: &item.name.0)
        
        if name.contains("Exile") {
            var bl_item = conn_to_bl_item(&item)
            bl_item_ref = bl_item
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
                var bl_item = self.bl_item_ref!
                
                add_connitem(get_blocklist(), &bl_item)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                    let item = get_connlist_item(get_blocklist(), Int32(0))
                    del_connitem(get_blocklist(), item)
                    
                    let size = Int(get_connlist_size(get_blocklist()))
                    print("check size: \(size)")
                    print("ASD")
                }
            }
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

        if tableColumn == tableView.tableColumns[2] {
            cellIdentifier = "ButtonCell"
        }

        let cellId = NSUserInterfaceItemIdentifier(rawValue: cellIdentifier)
        if cellIdentifier == "ButtonCell" {
            guard let cell = tableView.makeView(withIdentifier: cellId, owner: self) as? blButton else { print("WARNING: problem in activeConns getting button cell"); return nil }
            cell.bl_item = bl_item // take a copy so ok to free() later
            cell.title = String(cString: &item.name.0)

            cell.action = #selector(buttonClick(_:))
            return cell
        }
        return nil
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
}

import Cocoa

class blButton: NSButton {
    // we extend NSButton class to allow us to store a
    // pointer to the log entry that the row containing
    // the button refers to.  this is needed because the
    // log may be updated between the time the button is
    // created and when it is pressed. and so just using
    // the row of the log to identify the item may fail
    // (plus we can only store integers in button tag
    // property)
    var bl_item: bl_item_t?

    func clickButton() {
        guard var bl_item = self.bl_item else { print("WARNING: click blButton problem getting bl_item"); return }

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

        if title.contains("Allow") {
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
