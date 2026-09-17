<p align="center">
  <img src="data/intro.png" alt="Hyprkey" width="620">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Linux-1A1C1E?style=for-the-badge&logo=linux&logoColor=FFFFFF" alt="Linux">
  <img src="https://img.shields.io/badge/Wayland-1A1C1E?style=for-the-badge&logo=wayland&logoColor=FFFFFF" alt="Wayland">
  <img src="https://img.shields.io/badge/X11-1A1C1E?style=for-the-badge&logo=xorg&logoColor=FFFFFF" alt="X11">
  <img src="https://img.shields.io/badge/Python-1A1C1E?style=for-the-badge&logo=python&logoColor=FFFFFF" alt="Python">
  <img src="https://img.shields.io/badge/License-MIT-1A1C1E?style=for-the-badge&labelColor=1A1C1E&color=2F3033" alt="License">
</p>

A lightweight mechanical keyboard and mouse sound generator for Linux. Instead of looping static audio samples, Hyprkey synthesizes every keypress and click in real time with near-zero latency.

<p align="center">
  <img src="data/preview.png" alt="Hyprkey Window Preview" width="360">
</p>

---

### Features

* **Procedural Audio** — No bloated `.wav` sound packs. Audio is generated on the fly with virtually no delay.
* **14 Switch Profiles** — Tuned for creamy, deep, and thocky profiles (Boba Jelly, Creamy Butter, Deep Thock, Marshmallow, Rain Drop, Topre, and more).
* **Headphone / IEM Mode** — Tames harsh high-end transients so your ears don't get fatigued.
* **Mouse Clicks** — Responsive click synthesis for mouse buttons.
* **Live Synth Controls** — 8 real-time sliders to tweak frequency, click transient, warmth, decay, pitch drop, duration, softness, and body resonance.

---

<p align="center">
  <img src="data/install.png" alt="Installation" width="620">
</p>

### Installation

Run in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/rootscripts/hyprkey/main/install.sh | bash
