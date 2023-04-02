# GTrack - Head tracking for Garry's Mod
## Dependencies:
- [luasocket binary](https://github.com/danielga/gmod_luasocket/releases/)
    - 64 bit binary can be downloaded [here](https://f001.backblazeb2.com/file/cheezus-sharex/ShareX/2022/11/gmcl_socket.core_win64.dll) (or built from the above repository yourself)
- [luasocket lua files](https://github.com/danielga/gmod_luasocket)
    - Clone the luasocket repository
    - Merge the `includes` folder into your GMod's `lua` folder
- [opentrack](https://github.com/opentrack/opentrack)

## Setup:
1. Install this addon into your addons folder.
2. Install opentrack and set it up with your preferred head tracking solution. Many guides can be found online. Personally, I am using [AITrack](https://github.com/AIRLegend/aitrack/releases) alongside an old webcam.
3. Install the luasocket binary + lua files into your Garry's Mod folder, downloads linked in the requirements above.
4. In opentrack, set the output to `UDP over network`, press the configuration button, and set the remote IP address to `127.0.0.1` and the port to `4243` (or any value between 1024-65535).
5. In Garry's Mod, open the Q menu, navigate to `Options -> GTrack`, configure the port, and enable head tracking. Have fun!

## Issues:
- opentrack is running, yet I can't connect in GMod
    - Ensure the port opentrack is using is the same as the one configured in GTrack
    - Add an outbound rule in Windows Firewall allowing opentrack.exe through
