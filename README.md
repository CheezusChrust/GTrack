# GTrack - Head tracking for Garry's Mod
## Dependencies:
- luasocket binary (place in `steamapps/common/GarrysMod/garrysmod/lua/bin/`, create `bin` folder if it does not exist)
    - [64 bit](https://f001.backblazeb2.com/file/cheezus-sharex/ShareX/2022/11/gmcl_socket.core_win64.dll)
    - [32 bit](https://github.com/danielga/gmod_luasocket/releases/download/r1/gmcl_socket.core_win32.dll)
- [luasocket lua files](https://f001.backblazeb2.com/file/cheezus-sharex/ShareX/2023/10/24/43287023/luasocket.7z) (if on a server, only the server needs this)
    - This link is a pre-packaged addon containing the required luasocket files, place it in your addons folder after extracting
- [opentrack](https://github.com/opentrack/opentrack)

## Setup:
1. Install this addon into your addons folder.
2. Install the luasocket binary + lua files as directed above.
3. Install opentrack and set it up with your preferred head tracking solution. Many guides can be found online. Personally, I have used both [AITrack](https://github.com/AIRLegend/aitrack/releases) alongside an old webcam, and the [smoothtrack](https://smoothtrack.app/) ($10 USD) app.
4. In opentrack, set the output to `UDP over network`, press the configuration button, and set the remote IP address to `127.0.0.1` and the port to `4243` (or any value between 1024-65535).
5. In Garry's Mod, open the Q menu, navigate to `Options -> GTrack`, configure the port, and enable head tracking. Have fun!

## Issues:
- opentrack is running, yet I can't connect in GMod
    - Ensure the port opentrack is using is the same as the one configured in GTrack
    - Add an outbound rule in Windows Firewall allowing opentrack.exe through
