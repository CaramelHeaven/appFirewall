# MacLogout

My personal ideas.

## How to build
Just read about SMJobBlessUtil and write something like this:
```
./SMJobBlessUtil.py setreq /Users/[your name]/Library/Developer/Xcode/DerivedData/[your App Here]/Build/Products/Debug/MacLogout.app /pathTo/MacLogout/Info.plist /pathToMacLogout/com.caramelheaven.MacLogout-Helper/Info.plist
```

To verify if u all done in the right way:
```
./SMJobBlessUtil.py check /Users/[your name]/Library/Developer/Xcode/DerivedData/[your App Here]/Build/Products/Debug/MacLogout.app
```

If u still have a struggle with building please read README here https://github.com/aronskaya/smjobbless
Or a more detailed explanation about privilege helper
https://www.woodys-findings.com/posts/cocoa-implement-privileged-helper

### Authors
The author who integrated the basic logic
[Doug Leith](https://www.scss.tcd.ie/doug.leith)

## License

[BSD 3 License](https://opensource.org/licenses/BSD-3-Clause)

