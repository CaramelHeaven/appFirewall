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
    var popover = NSPopover()
    var popoverRow: Int = -1

    func appViewDidLoad(tableView: NSTableView?, tab: Int, ascKey: String, sortKeys: [String]) {
        appTableView = tableView
        appTableView!.dataSource = self
        appTableView!.delegate = self
    }

    func appViewWillAppear() {
        // window is opening, populate it with content
        // restore to previous size
        view.window?.setFrameUsingName("connsView")
        // record active tab
        
        // MARK: - RESRESHING of connections list every 1s
        timer = Timer.scheduledTimer(timeInterval: Config.viewRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
        refresh(timer: nil)
    }

    override func viewWillDisappear() {
        // print("viewWillDisappear")
        view.window?.saveFrame(usingName: "connsView") // record size of window
        timer.invalidate()
        super.viewWillDisappear()
    }

    @objc func refresh(timer: Timer?) {}

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
        
        return row
    }

    func invMapRow(r: Int) -> Int {
        // map from row in list to displayed row
        let log_last = numTableRows() - 1
        if r < 0 { return 0 }
        if r > log_last { return log_last }
        
        return r
    }

    func getTableCell(tableView: NSTableView, tableColumn: NSTableColumn?, row: Int) -> NSView? { return nil }
}

extension appViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return numTableRows()
    }
}

extension appViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        return getTableCell(tableView: tableView, tableColumn: tableColumn, row: row)
    }
}
