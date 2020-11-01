# MacPoe
test.

## How to build

Read here https://github.com/aronskaya/smjobbless
Or here https://www.woodys-findings.com/posts/cocoa-implement-privileged-helper



Example:
```
./SMJobBlessUtil.py setreq \
"/Users/alexisbridoux/Library/Developer/Xcode/DerivedData/Scriptex-hfw.../Build/Products/Debug/Scriptex.app" \
"~/Documents/Blog/Tutos/Privileged Helper/Scriptex final/Scriptex/Info.plist" \
"~/Documents/Blog/Tutos/Privileged Helper/Scriptex final/Helper/Info.plist"
```

Moreover SMJobBlessUtil also allow u to verify if build is successful or not with a `check` command
```
./SMJobBlessUtil.py check \ /Users/[urName]/Library/Developer/Xcode/DerivedData/PoeMac-Lalala/Build/Products/Debug PoeMac.app
```

Use `./uninstall_privileged_helper.sh` to clean build


### Authors
The author who integrated the basic magic
[Doug Leith](https://www.scss.tcd.ie/doug.leith)

## License

[BSD 3 License](https://opensource.org/licenses/BSD-3-Clause)

