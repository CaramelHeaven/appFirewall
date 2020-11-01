//
//  PoeWatcher.swift
//  appFirewall
//
//  Created by Sergey Fominov on 10/17/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

import Cocoa
import Foundation

class PoeWatcher {
    static let shared = PoeWatcher()

    private var timer: Timer = Timer()
    private var itemRef: bl_item_t?

    private var appDelegate: AppDelegate?

    private init() { }

    func startListening() {
        start_pid_watcher()

        appDelegate = NSApplication.shared.delegate as? AppDelegate

        timer = Timer.scheduledTimer(timeInterval: Config.viewRefreshTime, target: self, selector: #selector(refreshPids(timer:)), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late

        refreshPids(timer: nil)
    }

    func resetPoe() {
        guard var bl_item = itemRef else {
            appDelegate?.updatePoeStatus(.isNotWork)
            return
        }
        add_connitem(get_blocklist(), &bl_item)

        // We need to wait for unblock, 'cause immediatly unblocking isn't working
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000)) {
            let item = get_connlist_item(get_blocklist(), Int32(0))
            del_connitem(get_blocklist(), item)
        }
    }

    @objc private func refreshPids(timer: Timer?) {
        guard Int(get_pid_changed()) != 0 else {
            return
        }

        clear_pid_changed()
        update_gui_pid_list()

        let value = numberOfConnections()
        guard value > 0 else {
            return
        }

        findPoe(upperBound: value)
    }

    private func numberOfConnections() -> Int {
        return Int(get_num_gui_conns())
    }
}

fileprivate extension PoeWatcher {
    func findPoe(upperBound: Int) {
        for i in 0...upperBound {
            let row = Int32(mapRow(row: i))
            var item = get_gui_conn(row)

            let pidName = String(cString: &item.name.0)

            guard pidName.contains("Exile") else {
                continue
            }

            itemRef = conn_to_bl_item(&item)
            appDelegate?.updatePoeStatus(.isWork)

            return
        }

        appDelegate?.updatePoeStatus(.isNotWork)
    }
}

// Dont want to figure out what is really do for now
fileprivate extension PoeWatcher {
    func mapRow(row: Int) -> Int {
        // map from displayed row to row in list itself
        let log_last = numberOfConnections() - 1
        if row < 0 { return 0 }
        if row > log_last { return log_last }

        return row
    }
}
