//
//  SettingsViewController.swift
//  appFirewall
//
//  Created by Doug Leith on 22/12/2019.
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import Cocoa

class SettingsViewController: NSViewController {
    @IBOutlet weak var autoCheckUpdates: NSButton!
    @IBOutlet weak var autoUpdate: NSButton!
    @IBOutlet weak var runAtLogin: NSButton!
    @IBOutlet weak var useMenuBar: NSButton!
    @IBOutlet weak var blockQUIC: NSButton!
    @IBOutlet weak var useDOH: NSButton!
    var timer: Timer = Timer()

    func boolToState(value: Bool) -> NSControl.StateValue {
        if value {
            return .on
        } else {
            return .off
        }
    }

    func stateToBool(state: NSControl.StateValue) -> Bool {
        if state == .on {
            return true
        } else {
            return false
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        autoCheckUpdates.state = boolToState(value: Config.getAutoCheckUpdates())
        autoUpdate.state = boolToState(value: Config.getAutoUpdate())
        runAtLogin.state = boolToState(value: Config.getRunAtLogin())
        useMenuBar.state = boolToState(value: Config.getUseMenuBar())
        blockQUIC.state = boolToState(value: Config.getBlockQUIC())
        useDOH.state = boolToState(value: Config.getDnscrypt_proxy())

        timer = Timer.scheduledTimer(timeInterval: Config.settingsRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
    }

    override func viewWillDisappear() {
        // stop checking alignment of our settings with those on helper
        // when window closes - presumably any issues will mostly arise when
        // settings are changed (which means window is open), and this way
        // we avoid burden of continually contacting helper.
        // TO DO: or would it be better to leave checking active in case
        // the situation changes under our feet e.g. user changes firewall
        // settingd and breaks QUIC blocking ??
        timer.invalidate()
        super.viewWillDisappear()
    }

    @IBAction func autoCheckUpdatesClick(_ sender: NSButton!) {
        Config.autoCheckUpdates(value: stateToBool(state: autoCheckUpdates.state))
        Config.refresh(opts: [.timedCheckForUpdate])
    }

    @IBAction func autoUpdateClick(_ sender: Any) {
        Config.autoUpdate(value: stateToBool(state: autoUpdate.state))
    }

    @IBAction func runAtLoginClick(_ sender: Any) {
        Config.runAtLogin(value: stateToBool(state: runAtLogin.state))
        Config.refresh(opts: [.runAtLogin])
    }

    @IBAction func useMenuBarClick(_ sender: Any) {
        Config.useMenuBar(value: stateToBool(state: useMenuBar.state))
        Config.refresh(opts: [.menuBar])
        // update UI to show actual state after refresh
        useMenuBar.state = boolToState(value: Config.getUseMenuBar())
    }

    @IBAction func blockQUICClick(_ sender: Any) {
        Config.blockQUIC(value: stateToBool(state: blockQUIC.state))
        Config.refresh(opts: [.blockQUIC])
        // update UI to show actual state after refresh
        blockQUIC.state = boolToState(value: Config.getBlockQUIC())
    }

    @IBAction func DoHClick(_ sender: Any) {
        Config.dnscrypt_proxy(value: stateToBool(state: useDOH.state))
        Config.refresh(opts: [.dnscrypt_proxy])
        // update UI to show actual state after refresh
        useDOH.state = boolToState(value: Config.getDnscrypt_proxy())
    }

    @objc func refresh(timer: Timer?) {
        // confirm that our settings match up with the facts on the ground,
        // and if not generate error messages and update as appropriate
        Config.checkDnscrypt_proxy_status()
        useDOH.state = boolToState(value: Config.getDnscrypt_proxy())
        Config.checkBlockQUIC_status()
        blockQUIC.state = boolToState(value: Config.getBlockQUIC())
    }
}
