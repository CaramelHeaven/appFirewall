//
//  MainViewModel.swift
//  appFirewall
//
//  Created by Sergey Fominov on 10/15/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

import Foundation

class MainViewModel: ObservableObject {
    
    var bl_item_ref: bl_item_t?

    init() {
        
    }

    func findPoeAndKill() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(0)) {
            var bl_item = self.bl_item_ref!

            add_connitem(get_blocklist(), &bl_item)

            let size = Int(get_connlist_size(get_blocklist()))
            print("check size: \(size)")
            print("--------------")

            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                let item = get_connlist_item(get_blocklist(), Int32(0))
                del_connitem(get_blocklist(), item)

                let size = Int(get_connlist_size(get_blocklist()))
                print("check size: \(size)")
                print("ASD")
            }
        }
    }

    func catchPid(row: Int) {
        let r = mapRow(row: row)
        var item = get_gui_conn(Int32(r))

        let name = String(cString: &item.name.0)
        print("name: \(name)")

        if name.contains("Exile") {
            let bl_item = conn_to_bl_item(&item)
            bl_item_ref = bl_item
        }
    }

    func showPids() {
        let value = numTableRows()
        guard value > 0 else {
            return
        }

        for i in 0...value {
            catchPid(row: i)
        }
    }

    @objc func refresh(timer: Timer?) {
        guard Int(get_pid_changed()) != 0 else {
            return
        }

        clear_pid_changed()
        update_gui_pid_list()

        showPids()
    }

    func numTableRows() -> Int {
        return Int(get_num_gui_conns())
    }

    func mapRow(row: Int) -> Int {
        // map from displayed row to row in list itself
        let log_last = numTableRows() - 1
        if row < 0 { return 0 }
        if row > log_last { return log_last }

        return row
    }
}
