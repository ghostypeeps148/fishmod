# fishmod
fishmod is kinda a continuation of murkmod, a continuation of fakemurk and mush that includes additional useful utilities to help turn ChromeOS into a more traditional Linux distribution. It also removes all of the original murking features; for that, you should probably use modmium when it comes out. (I will try to make this compatible with modmium if possible)

the original can be found [here](https://github.com/crosbreaker/murkmodTempFix)
the original-er can be found [here](https://github.com/rainestorme/murkmod)
## Installation

> [!NOTE]
> You should have unblocked developer mode in some capacity before following the instructions below, most likely by setting your GBB flags to `0x80b1` (recommended), `0x8000`, `0x8090`, or `0x8091`.

Enter developer mode and boot into ChromeOS. Connect to WiFi, but don't log in. Open VT2 by pressing `Ctrl+Alt+F2 (Forward)` and log in as `root`. Run the following command:

```sh
bash <(curl -SLk https://raw.githubusercontent.com/ghostypeeps148/fishmod/refs/heads/main/install.sh)
```
Once the installation is complete, the system will reboot into fishmod.

It is also highly reccomended to install the fishmod helper extension. To do so, upload the 'helper' folder that will be added to your Downloads post-installation as an unpacked extension.

> Recovery image data provided by [MercuryWorkshop](https://github.com/MercuryWorkshop/chromeos-releases-data?tab=CC-BY-4.0-1-ov-file). Thanks!

## Features

- Plugin manager
   - Multiple supported languages: Bash and JavaScript (Python support is in the works)
   - Easy system development: Plugins can run as daemons in the background, upon startup, or when a user triggers them
   - Simple API: Read the docs [here](https://github.com/ghostypeeps148/fishmod/blob/main/docs/plugin_dev.md)
- Support for the newest versions of ChromeOS
- Improved privacy (Analytics completely removed and no automatic updates)
- Installation from VT2 via the devmode installer
- Graphical helper extension
- Support to modify root files through the file manager
- Real native application support
- Seamless updating without breaking any changes you choose to make
- Integrated Chromebrew
- and fish.
