//
//  appViewController.swift
//  appFirewall
//
//  Created by Doug Leith on 12/12/2019.
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import Cocoa

class appViewController: NSViewController {
    var appTableView: NSTableView?
    var timer: Timer = Timer()
    var asc: Bool = true // whether shown in ascending/descending order
    var popover = NSPopover()
    var popoverRow: Int = -1
    var selectedRowHashes: [String] = []
    var popoverHash: String = ""
    var toolTipsEnabled: Bool = true
    var tab: Int = 0
    var ascKey: String = ""
    var sortKey: String? = ""
    var sortKeys: [String] = []

    func appViewDidLoad(tableView: NSTableView?, tab: Int, ascKey: String, sortKeys: [String]) {
        // Do basic setup after loading the view.
        self.tab = tab
        self.ascKey = ascKey
        self.sortKeys = sortKeys
        let menu = NSMenu()

        // force using ! since shouldn't fail here and its serious if it does
        guard tableView != nil else {
            print("ERROR: appViewDidLoad() tableView is nil!")
            exit_popup(msg: "Internal Error: appViewDidLoad() tableView is nil!", force: 0) // this won't return
            return // to avoid compiler warning
        }
        appTableView = tableView
        appTableView?.menu = menu
        appTableView!.dataSource = self
        appTableView!.delegate = self
        // allow drag and drop of URLs
        appTableView!.registerForDraggedTypes([.URL, .fileURL])
    }

    func appViewWillAppear() {
        // window is opening, populate it with content
        // restore to previous size
        view.window?.setFrameUsingName("connsView")
        // record active tab
        UserDefaults.standard.set(tab, forKey: "tab_index")
        // enable click of column header to call sortDescriptorsDidChange action below
        asc = UserDefaults.standard.bool(forKey: ascKey)
        if appTableView?.tableColumns[0].sortDescriptorPrototype == nil {
            appTableView?.tableColumns[0].sortDescriptorPrototype = NSSortDescriptor(key: sortKeys[0], ascending: asc)
            appTableView?.tableColumns[1].sortDescriptorPrototype = NSSortDescriptor(key: sortKeys[1], ascending: asc)
        }
        // schedule refresh of connections list every 1s
        timer = Timer.scheduledTimer(timeInterval: Config.viewRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
        refresh(timer: nil)
    }

    override func viewWillDisappear() {
        // print("viewWillDisappear")
        save_state()
        view.window?.saveFrame(usingName: "connsView") // record size of window
        timer.invalidate()
        super.viewWillDisappear()
    }

    @objc func refresh(timer: Timer?) {}

    func saveSelected() {
        // save set of currently selected rows
        let indexSet = appTableView?.selectedRowIndexes ?? []
        selectedRowHashes = []; popoverHash = ""
        for row in indexSet {
            guard let cell = appTableView?.view(atColumn: 2, row: row, makeIfNecessary: true) as? blButton else { continue }
            selectedRowHashes.append(cell.hashStr)
            if popover.isShown && popoverRow == row {
                print("popover active for row ", row)
                popoverHash = cell.hashStr
            }
        }
    }

    func selectall(sender: AnyObject?) {
        appTableView?.selectAll(nil)
    }

    func getRowText(row: Int) -> String {
        guard let cell0 = appTableView?.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView else { return "" }
        guard let str0 = cell0.textField?.stringValue else { return "" }
        guard let cell1 = appTableView?.view(atColumn: 1, row: row, makeIfNecessary: true) as? NSTableCellView else { return "" }
        let str1 = cell1.textField?.stringValue ?? ""
        let tip = cell1.textField?.toolTip ?? ""
        return str0 + " " + str1 + " [" + tip + "]\n"
    }

    @objc func copyLine(sender: AnyObject?) {
        guard let indexSet = appTableView?.selectedRowIndexes else { print("WARNING: problem in copyLine getting index set"); return }
        var text = ""
        for row in indexSet {
            text += getRowText(row: row)
        }
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.setString(text, forType: NSPasteboard.PasteboardType.string)
    }

    @objc func pasteLine(sender: AnyObject?) {}

    @objc func updateTable(rowView: NSTableRowView, row: Int) {
        // update all of the buttons in table (called after
        // pressing a button changes blacklist state etc)
        guard let cell2 = rowView.view(atColumn: 2) as? blButton else { print("WARNING: problem in updateTable getting cell 2 for row ", row); return }
        cell2.updateButton()

        guard let cell1 = rowView.view(atColumn: 1) as? NSTableCellView else { print("WARNING: problem in updateTable getting cell 1"); return }
        if !toolTipsEnabled {
            cell1.textField?.toolTip = ""
        } else {
            cell1.textField?.toolTip = cell2.tip
        }
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

    func numTableRows() -> Int { return 0 }

    func mapRow(row: Int) -> Int {
        // map from displayed row to row in list itself
        let log_last = numTableRows() - 1
        if row < 0 { return 0 }
        if row > log_last { return log_last }
        if asc {
            return row
        } else {
            return log_last - row
        }
    }

    func invMapRow(r: Int) -> Int {
        // map from row in list to displayed row
        let log_last = numTableRows() - 1
        if r < 0 { return 0 }
        if r > log_last { return log_last }
        if asc {
            return r
        } else {
            return log_last - r
        }
    }

    func getTableCell(tableView: NSTableView, tableColumn: NSTableColumn?, row: Int) -> NSView? { return nil }
}

extension appViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return numTableRows()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sortDescriptor = tableView.sortDescriptors.first else {
            print("WARNING: problem getting sort descriptor"); return
        }
        asc = sortDescriptor.ascending
        UserDefaults.standard.set(asc, forKey: ascKey)
        sortKey = sortDescriptor.key
        if asc != oldDescriptors.first?.ascending {
            refresh(timer: nil)
        }
    }
}

extension appViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return getTableCell(tableView: tableView, tableColumn: tableColumn, row: row)
    }
}
