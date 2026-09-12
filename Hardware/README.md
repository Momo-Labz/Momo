# MOMO LABZ Agent Desk prototype

This turns MOMO into a small, private, always-visible status object. The Mac does the scanning; the desk unit only opens a read-only page over the local network.

## Reference hardware

- Raspberry Pi Zero 2 W (65 × 30 mm, Wi-Fi): <https://www.raspberrypi.com/products/raspberry-pi-zero-2-w/>
- Waveshare 3.5-inch RPi LCD (B), 480 × 320 IPS touch display: <https://www.waveshare.com/3.5inch-rpi-lcd-b.htm>
- 16 GB or larger microSD card
- 5 V micro-USB supply
- 40-pin header for a Pi Zero 2 W without one fitted
- M2.5 nylon standoffs or thin VHB tape for the first enclosure test

The enclosure is deliberately parametric. Display boards sold under similar names can move connectors or mounting holes, so measure the real PCB before a final print.

## Pair and run

1. In the Mac app, open **Settings → Desk Display** and enable the local display.
2. Copy its paired address or scan the QR code. The long key is intentional; the six-character code is only a visual match check.
3. On Raspberry Pi OS, install the display driver according to Waveshare's instructions and confirm the desktop is 480 × 320.
4. Create `/home/barboy/.config/barboy/display-url` containing the single paired address.
5. Copy `launch-display.sh` to `/usr/local/bin/launch-barboy-display`, make it executable, and install `barboy-kiosk.service` under `/etc/systemd/system/`.
6. Enable it with `sudo systemctl enable --now barboy-kiosk.service`.

The server is off by default, binds only while the feature is enabled, exposes read-only status, and redacts work titles when that privacy toggle is off. Keep the Mac and screen on a trusted local network.

## Print

The provided STLs are an intentionally blocky first prototype sized around a 100 × 72 × 28 mm body with a 74 × 50 mm viewing aperture. Print the body face-down, the back flat, and the stand flat.

- Material: PLA or PETG
- Layer height: 0.20 mm
- Walls: 3
- Infill: 15–20%
- Supports: none for the pixel prototype
- Fit allowance: 0.35 mm in the parametric OpenSCAD source

Run `python3 Enclosure/export_pixel_stl.py` to regenerate the dependency-free STL set. For a different module, edit the dimensions near the top of `Enclosure/bar-boy-display.scad` and export `part="body"`, `part="back"`, and `part="stand"` in OpenSCAD.
