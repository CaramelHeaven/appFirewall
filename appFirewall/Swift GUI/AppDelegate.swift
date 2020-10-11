//
//  AppDelegate.swift
//  appFirewall
//
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import Cocoa
import os
import ServiceManagement

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    // --------------------------------------------------------
    // private variables
    // timer for periodic polling ...
    var timer: Timer = Timer()
    var count_stats: Int = 0
    // menubar button ...
    var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func currentAppViewController() -> appViewController? {
        guard let tc: NSTabViewController = NSApp.mainWindow?.contentViewController as? NSTabViewController else {
            print("ERROR on copy: problem getting tab view controller")
            return nil
        }

        let i = tc.selectedTabViewItemIndex
        let v = tc.tabViewItems[i] // the currently active TabViewItem
        guard let c = v.viewController as? appViewController else {
            print("ERROR on copy: problem getting view controller")
            return nil
        }

        return c
    }

    @IBAction func restartHelper(_ sender: Any) {
        UserDefaults.standard.set(true, forKey: "force_helper_restart")
        restart_app()
    }

    @objc func openapp(_ sender: Any?) {
        // reopen window

        // if window already exists,and it should since we don't
        // release it on close, then we just reopen it.
        // hopefully this should work almost all of the time
        // (seems like an error if it doesn't work)
        for window in NSApp.windows {
            print(window, window.title)
            // as well as the main window the status bar button has a window
            if window.title == "appFirewall" {
                print("openapp() restoring existing window")
                window.makeKeyAndOrderFront(self) // bring to front

                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        print("WARNING: openapp() falling back to creating new window")
    }

    @objc func refresh() {
        // note: state is saved on window close, no need to do it here
        // (and if we do it here it might be interrupted by a window
        // close event and lead to file corruption

        // check if listener thread (for talking with helper process that
        // has root privilege) has run into trouble -- if so, its fatal
        if Int(check_for_error()) != 0 {
            print("CRUSH")
//            exit_popup(msg: String(cString: get_error_msg()), force: Int(get_error_force()))
            // this call won't return
        }
        // update menubar button tooltip
        if let button = statusItem.button {
            button.toolTip = "appFirewall (" + String(get_num_conns_blocked()) + " blocked)"
        }
    }

    // --------------------------------------------------------
    // application event handlers

    func resetDefaults() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        dictionary.keys.forEach { key in
            defaults.removeObject(forKey: key)
        }
    }

    func applicationWillFinishLaunching(_ aNotification: Notification) {
//        resetDefaults()

        // create storage dir if it doesn't already exist
        make_data_dir()

        // redirect C logging from stdout to logfile.  do this early but
        // important to call make_data_dir() first so that logfile has somewhere to live
        redirect_stdout(Config.appLogName)

        UserDefaults.standard.register(defaults: ["first_run": true])
        let first = UserDefaults.standard.bool(forKey: "first_run")
        if first || Config.testFirst {
            // things to do on first run of app
            if Config.enableConsentForm > 0 {
                // get consent or exit, we check for this early of course
                //				let storyboard = NSStoryboard(name:"Main", bundle:nil)
                //				let controller : ConsentViewController = storyboard.instantiateController(withIdentifier: "ConsentViewController") as! ConsentViewController
                //				let window = NSWindow(contentViewController: controller)
                //				window.styleMask.remove(.miniaturizable)
                //				window.styleMask.remove(.resizable) // fixed size
                //				// now block here until either user gives consent or the app exits
                //				NSApp.runModal(for: window)
            }
            // log basic security settings (SIP, gatekeeper etc)
            DispatchQueue.global(qos: .background).async {
//                getSecuritySettings()
            }
            UserDefaults.standard.set(false, forKey: "first_run")
        }

        // set default logging level, again do this early
        UserDefaults.standard.register(defaults: ["logging_level": Config.defaultLoggingLevel])
        // can change this at command line using "defaults write" command
        let log_level = UserDefaults.standard.integer(forKey: "logging_level")
        set_logging_level(Int32(log_level))
        init_stats() // must be done before any C threads are fired up

        let restart = UserDefaults.standard.bool(forKey: "restart")
        if restart {
            print("Restarting ...")
            UserDefaults.standard.set(false, forKey: "restart")
            var count = 0
            while is_app_already_running() {
                sleep(1) // allow time for previous instance to stop
                count = count + 1
                if count > 5 { break }
            }
            print("count = ", count)
        }
        let lol = is_app_already_running()
        if lol {
//            exit_popup(msg: "appFirewall is already running!", force: 0)
        }

        // useful for debugging
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        print("appFirewall version: ", appVersion ?? "<not found>")
        // for debugging
        print("process: ")
        print("environment ", ProcessInfo.processInfo.environment)

        UserDefaults.standard.register(defaults: ["signal": -1])
        UserDefaults.standard.register(defaults: ["logcrashes": 1])
        let sig = UserDefaults.standard.integer(forKey: "signal")
        if (sig > 0) {
            // we had a crash !
            if let backtrace = UserDefaults.standard.object(forKey: "backtrace") as? [String], let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                print("had a crash with signal ", sig, " for code release ", version)
                backtrace.forEach { print($0) }
                print("continuing")
                // send report to www.leith.ie/logcrash.php.  post "backtrace=<>&version=<>"]
                var request = URLRequest(url: Config.crashURL); request.httpMethod = "POST"
                var str: String = ""
                for s in backtrace {
                    str = str + s + "\n"
                }
                let uploadData = ("signal=" + String(sig) + "&backtrace=" + str + "&version=" + version).data(using: .ascii)
                let session = URLSession(configuration: .default)
                let task = session.uploadTask(with: request, from: uploadData)
                { _, response, error in
                    if let error = error {
                        print("error when sending backtrace: \(error)")
                        return
                    }
                    if let resp = response as? HTTPURLResponse {
                        if !(200...299).contains(resp.statusCode) {
                            print("server error when sending backtrace: ", resp.statusCode)
                        }
                    }
                }
                task.resume()
                session.finishTasksAndInvalidate()
                // and clear, so we don't come back here
                UserDefaults.standard.set(-1, forKey: "signal")
            } else {
                print("problem getting backtrace or version from userdefaults after crash")
            }
        }

        // set up handler to catch errors.
        setup_sig_handlers()

        // install appFirewall-Helper, if not already installed
        UserDefaults.standard.register(defaults: ["force_helper_restart": false])
        let force = UserDefaults.standard.bool(forKey: "force_helper_restart")
        start_helper(force: force)
        // reset, force is one time only
        UserDefaults.standard.set(false, forKey: "force_helper_restart")

        /* // setup menubar action
         let val = UserDefaults.standard.integer(forKey: "Number of connections blocked")
         set_num_conns_blocked(Int32(val))
         if let button = statusItem.button {
         	button.image = NSImage(named:NSImage.Name("StatusBarButtonImage"))
         	if (button.image == nil) {
         		print("Menubar button image is nil, falling back to using builtin image")
         		// fall back to using a builtin icon, this should always work
         		button.image = NSImage(named:NSImage.Name(NSImage.quickLookTemplateName))
         		if (button.image == nil) {
         			print("Menubar button image is *still* nil")
         		}
         	}
         	button.toolTip="appFirewall ("+String(get_num_conns_blocked())+" blocked)"
         	button.action = #selector(openapp(_:))
         } else {
         	print("Problem getting menubar button, ", statusItem, statusItem.button ?? "nil")
         } */

        // set default display state for GUI
        UserDefaults.standard.register(defaults: ["active_asc": true])
        UserDefaults.standard.register(defaults: ["blocklist_asc": true])
        UserDefaults.standard.register(defaults: ["log_asc": false])
        UserDefaults.standard.register(defaults: ["log_show_blocked": 3])

        // set whether to use dtrace assistance or not
        UserDefaults.standard.register(defaults: ["dtrace": Config.enableDtrace])
        let sipEnabled = isSIPEnabled()
        print("SIP enabled: ", sipEnabled)
        var dtrace = UserDefaults.standard.integer(forKey: "dtrace")
        if sipEnabled { dtrace = 0 } // dtrace doesn't work with SIP
        if dtrace > 0 {
            print("Dtrace enabled")
        } else {
            dtrace = 0
            print("Dtrace disabled")
        }
        // set whether Nstat assistance is used
        UserDefaults.standard.register(defaults: ["nstat": Config.enableNstat])
        let nstat = UserDefaults.standard.integer(forKey: "nstat")
        if nstat > 0 {
            print("Nstat enabled")
        } else {
            print("Nstat disabled")
        }

        // reload state
        load_state()
        Config.initLoad()

        // start listeners
        // this can be slow since it blocks while making network connection to helper
        DispatchQueue.global(qos: .background).async {
            start_helper_listeners(Int32(dtrace), Int32(nstat))
        }

        // schedule house-keeping ...
        timer = Timer.scheduledTimer(timeInterval: Config.appDelegateRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("stopping")
        // viewWillDisappear() event is triggered for any open windows
        // and will call save_state(), so no need to do it again here
        stop_helper_listeners()
        if Config.getBlockQUIC() { unblock_QUIC() }
        if Config.getDnscrypt_proxy() { stop_dnscrypt_proxy() }
    }

    func applicationDidEnterBackground(_ aNotification: Notification) {
        // Insert code here to tear down your application
        // NB: don't think this function is *ever* called
        print("going into background")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // called when click on dock icon to reopen window
        openapp(nil)
        return true
    }
}
