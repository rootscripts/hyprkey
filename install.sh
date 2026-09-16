#!/usr/bin/env bash
set -e

APP_DIR="$HOME/.config/hyprkey"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
VENV_DIR="$APP_DIR/venv"

mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"

echo "==> [1/4] Настройка прав доступа к вводу..."
if [ ! -f /etc/udev/rules.d/99-hyprkey-input.rules ]; then
    echo 'KERNEL=="event*", SUBSYSTEM=="input", MODE="0666"' | sudo tee /etc/udev/rules.d/99-hyprkey-input.rules >/dev/null
    sudo udevadm control --reload-rules && sudo udevadm trigger
fi
sudo chmod 666 /dev/input/event* 2>/dev/null || true

echo "==> [2/4] Подготовка окружения Python..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install -q PyQt6 numpy pygame evdev

echo "==> [3/4] Установка компонентов Hyprkey..."

cat << 'EOF' > "$APP_DIR/config.json"
{"muted": false, "preset": 0, "volume": 100, "mouse": true, "headset": false}
EOF

cat << 'EOF' > "$APP_DIR/custom.json"
{"freq": 380, "click": 2, "warm": 35, "decay": 75, "drop": 30, "dur": 35, "soft": 20, "body": 30}
EOF

cat << 'EOF' > "$APP_DIR/daemon.py"
import sys, os, signal, json, time, select
import numpy as np, pygame
from evdev import InputDevice, ecodes, list_devices

cfg_f = os.path.expanduser("~/.config/hyprkey/config.json")
cust_f = os.path.expanduser("~/.config/hyprkey/custom.json")
pid_f = os.path.expanduser("~/.config/hyprkey/daemon.pid")

with open(pid_f, "w") as f:
    f.write(str(os.getpid()))

try:
    pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=256)
    pygame.mixer.set_num_channels(128)
except Exception:
    sys.exit(1)

def make_pop(freq=480, dur=0.030, decay=0.0055, p_drop=0.40, click_mix=0.03, warm=0.30, vol=0.75, att=0.0018, body=0.0, hset=False):
    if hset:
        click_mix *= 0.15
        warm *= 1.15
        att = max(att, 0.0035)
    samples = int(44100 * dur)
    t = np.linspace(0, dur, samples, False)
    f = freq * (1.0 - p_drop * (1.0 - np.exp(-t / 0.008)))
    attack = np.clip(t / att, 0, 1)
    env = np.exp(-t / decay) * np.sin(np.pi * 0.5 * attack)
    wave = np.sin(2 * np.pi * f * t) + warm * np.sin(4 * np.pi * f * t) * np.exp(-t / (decay * 0.5))
    if body > 0:
        wave += body * np.sin(np.pi * f * t) * np.exp(-t / (decay * 0.8))
    trans = np.random.uniform(-1, 1, samples) * np.exp(-t / (0.0012 if hset else 0.0008))
    raw = (wave * (1.0 - click_mix) + trans * click_mix) * env
    if hset:
        filt = np.array([0.08, 0.25, 0.34, 0.25, 0.08])
        raw = np.convolve(raw, filt, mode="same")
    raw = np.clip(raw, -1.0, 1.0)
    pcm = (raw / (np.max(np.abs(raw)) + 1e-6) * 32767 * vol).astype(np.int16)
    stereo = np.column_stack((pcm, pcm))
    return pygame.sndarray.make_sound(stereo)

def create_palette(base_f, dur, decay, drop, click, warm, vol, att=0.0018, body=0.0, hset=False):
    return {
        "normal": [
            make_pop(base_f*0.96, dur, decay, drop, click, warm, vol, att, body, hset),
            make_pop(base_f*0.99, dur, decay, drop, click, warm, vol, att, body, hset),
            make_pop(base_f*1.02, dur, decay, drop, click, warm, vol, att, body, hset),
            make_pop(base_f*1.05, dur, decay, drop, click, warm, vol, att, body, hset)
        ],
        "space": make_pop(base_f*0.70, dur*1.35, decay*1.5, drop*0.9, click*0.8, warm*1.3, vol*1.1, att*1.2, body*1.3, hset),
        "back": make_pop(base_f*0.88, dur*0.95, decay*0.9, drop*0.8, click*0.8, warm*0.8, vol*0.9, att, body*0.8, hset),
        "mouse": make_pop(base_f*1.30, dur*0.8, decay*0.8, drop*1.2, click*1.3, warm*0.5, vol*0.9, att*0.9, body*0.5, hset)
    }

specs = [
    (480, 0.030, 0.0055, 0.45, 0.020, 0.25, 0.75, 0.0018, 0.15),
    (340, 0.038, 0.0080, 0.28, 0.015, 0.45, 0.85, 0.0020, 0.30),
    (440, 0.034, 0.0070, 0.52, 0.018, 0.35, 0.80, 0.0018, 0.20),
    (380, 0.032, 0.0060, 0.18, 0.025, 0.55, 0.80, 0.0016, 0.35),
    (270, 0.045, 0.0110, 0.20, 0.010, 0.25, 0.75, 0.0028, 0.20),
    (210, 0.040, 0.0090, 0.10, 0.015, 0.65, 0.95, 0.0018, 0.45),
    (550, 0.035, 0.0075, 0.60, 0.010, 0.18, 0.75, 0.0022, 0.10),
    (460, 0.030, 0.0050, 0.32, 0.020, 0.32, 0.80, 0.0017, 0.25),
    (310, 0.036, 0.0078, 0.24, 0.015, 0.50, 0.82, 0.0020, 0.30),
    (280, 0.036, 0.0075, 0.22, 0.025, 0.45, 0.85, 0.0016, 0.35),
    (230, 0.038, 0.0085, 0.20, 0.012, 0.55, 0.85, 0.0020, 0.40),
    (290, 0.036, 0.0080, 0.18, 0.015, 0.45, 0.85, 0.0020, 0.25),
    (220, 0.042, 0.0120, 0.06, 0.010, 0.65, 0.90, 0.0025, 0.35),
    (350, 0.033, 0.0065, 0.28, 0.020, 0.42, 0.80, 0.0018, 0.25)
]

profs = []
state = {"muted": False, "preset": 0, "volume": 100, "mouse": True, "headset": False}
last_hset = [None]

def load_config(signum=None, frame=None):
    global state, profs
    try:
        with open(cfg_f) as f:
            state = json.load(f)
        hset = state.get("headset", False)
        if last_hset[0] != hset or not profs:
            last_hset[0] = hset
            profs = [create_palette(*p, hset=hset) for p in specs]
            c = {}
            if os.path.exists(cust_f):
                with open(cust_f) as f:
                    c = json.load(f)
            profs.append(create_palette(c.get("freq", 380), c.get("dur", 35)/1000.0, c.get("decay", 75)/10000.0, c.get("drop", 30)/100.0, c.get("click", 2)/100.0, c.get("warm", 35)/100.0, 0.85, c.get("soft", 20)/10000.0, c.get("body", 30)/100.0, hset=hset))
        elif state.get("preset", 0) == len(profs) - 1 and os.path.exists(cust_f):
            with open(cust_f) as f:
                c = json.load(f)
            profs[-1] = create_palette(c.get("freq", 380), c.get("dur", 35)/1000.0, c.get("decay", 75)/10000.0, c.get("drop", 30)/100.0, c.get("click", 2)/100.0, c.get("warm", 35)/100.0, 0.85, c.get("soft", 20)/10000.0, c.get("body", 30)/100.0, hset=hset)
        vol = state.get("volume", 100) / 100.0
        for pr in profs:
            pr["space"].set_volume(vol)
            pr["back"].set_volume(vol)
            pr["mouse"].set_volume(vol)
            for s in pr["normal"]:
                s.set_volume(vol)
    except Exception:
        pass

signal.signal(signal.SIGUSR1, load_config)
load_config()

def get_kbs():
    kbs = {}
    for p in list_devices():
        try:
            d = InputDevice(p)
            caps = d.capabilities()
            if ecodes.EV_KEY in caps:
                keys = caps[ecodes.EV_KEY]
                if isinstance(keys, list) and (ecodes.KEY_A in keys or 272 in keys):
                    kbs[d.fd] = d
        except Exception:
            pass
    return kbs

devs = get_kbs()

while True:
    try:
        if not devs:
            time.sleep(1)
            devs = get_kbs()
            continue
        r, _, _ = select.select(devs.keys(), [], [], 2.0)
        for fd in r:
            for ev in devs[fd].read():
                if not state["muted"] and ev.type == ecodes.EV_KEY and ev.value == 1:
                    k = ev.code
                    p = profs[state["preset"]]
                    if k in (ecodes.KEY_SPACE, ecodes.KEY_ENTER):
                        p["space"].play()
                    elif k == ecodes.KEY_BACKSPACE:
                        p["back"].play()
                    elif k in (272, 273, 274, 275, 276):
                        if state.get("mouse", True):
                            p["mouse"].play()
                    elif k not in (ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT, ecodes.KEY_LEFTCTRL, ecodes.KEY_LEFTALT, ecodes.KEY_CAPSLOCK, ecodes.KEY_TAB, ecodes.KEY_ESC):
                        p["normal"][k % len(p["normal"])].play()
    except OSError:
        devs = get_kbs()
    except Exception:
        time.sleep(1)
EOF

cat << 'EOF' > "$APP_DIR/gui.py"
import sys, json, os, signal, math
from PyQt6.QtWidgets import QApplication, QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QComboBox, QSlider, QLabel, QFrame
from PyQt6.QtCore import Qt, QTimer, QVariantAnimation, QRectF, QPointF
from PyQt6.QtGui import QCursor, QPainter, QColor, QFont, QFontMetrics, QPen, QPolygonF

cfg_f = os.path.expanduser("~/.config/hyprkey/config.json")
cust_f = os.path.expanduser("~/.config/hyprkey/custom.json")
pid_f = os.path.expanduser("~/.config/hyprkey/daemon.pid")

PRESETS = ["iPhone Bubble", "Creamy Butter", "Boba Jelly", "Wooden Block", "Marshmallow", "Thocky Mech", "Rain Drop", "Ceramic Pebble", "Matcha Latte", "Holy Panda", "Gateron Black Ink", "Alpaca Linear", "Topre Silent", "Coffee Bean", "Custom (Expert)"]

class MBtn(QPushButton):
    def __init__(self):
        super().__init__()
        self.on = True
    def paintEvent(self, e):
        super().paintEvent(e)
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        c = QColor("#1A1C1E") if self.on else QColor("#74777F")
        p.setPen(QPen(c, 2.2, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
        p.setBrush(Qt.BrushStyle.NoBrush)
        cx, cy = self.width() / 2.0, self.height() / 2.0
        p.drawRoundedRect(QRectF(cx - 10, cy - 15, 20, 30), 10, 10)
        p.drawLine(QPointF(cx, cy - 15), QPointF(cx, cy - 7))
        p.setBrush(c)
        p.setPen(Qt.PenStyle.NoPen)
        p.drawRoundedRect(QRectF(cx - 1.8, cy - 11, 3.6, 7), 1.8, 1.8)

class HBtn(QPushButton):
    def __init__(self):
        super().__init__()
        self.on = False
    def paintEvent(self, e):
        super().paintEvent(e)
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        c = QColor("#1A1C1E") if self.on else QColor("#74777F")
        p.setPen(QPen(c, 2.2, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
        p.setBrush(Qt.BrushStyle.NoBrush)
        cx, cy = self.width() / 2.0, self.height() / 2.0
        p.drawArc(QRectF(cx - 10, cy - 10, 20, 20), 0, 180 * 16)
        p.setBrush(c)
        p.setPen(Qt.PenStyle.NoPen)
        p.drawRoundedRect(QRectF(cx - 12, cy - 3, 4.5, 10), 2, 2)
        p.drawRoundedRect(QRectF(cx + 7.5, cy - 3, 4.5, 10), 2, 2)

class VIcon(QWidget):
    def __init__(self):
        super().__init__()
        self.setFixedSize(20, 20)
    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        c = QColor("#E2E2E5")
        p.setBrush(c)
        p.setPen(Qt.PenStyle.NoPen)
        poly = QPolygonF([QPointF(2, 7), QPointF(6, 7), QPointF(11, 3), QPointF(11, 17), QPointF(6, 13), QPointF(2, 13)])
        p.drawPolygon(poly)
        p.setBrush(Qt.BrushStyle.NoBrush)
        p.setPen(QPen(c, 1.8, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
        p.drawArc(QRectF(7, 6, 8, 8), -50 * 16, 100 * 16)
        p.drawArc(QRectF(5, 3, 14, 14), -50 * 16, 100 * 16)

class JText(QWidget):
    def __init__(self):
        super().__init__()
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setFixedSize(210, 44)
        self.setStyleSheet("outline: none; border: none;")
        self.chars = []
        self.c_blink = 0.0
        self.t = QTimer()
        self.t.timeout.connect(self.anim)
        self.t.start(16)
        self.ct = QTimer()
        self.ct.setSingleShot(True)
        self.ct.timeout.connect(self.clear_text)
    def clear_text(self):
        for c in self.chars:
            c["op_t"] = 0.0
            c["d"] = True
    def keyPressEvent(self, e):
        if e.key() == Qt.Key.Key_Backspace:
            for c in reversed(self.chars):
                if not c.get("d"):
                    c["op_t"] = 0.0
                    c["d"] = True
                    break
        elif e.text() and e.text().isprintable():
            fm = QFontMetrics(self.font())
            cx = 15.0
            for c in self.chars:
                if not c.get("d"):
                    cx += fm.horizontalAdvance(c["c"])
            start_x = cx
            if cx > self.width() - 25:
                start_x = self.width() - 25
            self.chars.append({"c": e.text(), "x": float(start_x), "y": 15.0, "op": 0.0, "tx": 0.0, "op_t": 1.0, "d": False})
        self.update_t()
        self.ct.start(5000)
    def update_t(self):
        fm = QFontMetrics(self.font())
        cx = 15.0
        for c in self.chars:
            if not c.get("d"):
                c["tx"] = cx
                cx += fm.horizontalAdvance(c["c"])
        if cx > self.width() - 25:
            shift = cx - (self.width() - 25)
            for c in self.chars:
                c["tx"] -= shift
    def anim(self):
        self.c_blink += 0.15
        for c in self.chars[:]:
            if abs(c["x"] - c["tx"]) > 0.1:
                c["x"] += (c["tx"] - c["x"]) * 0.3
            if c["op_t"] == 0.0:
                c["y"] += (15.0 - c["y"]) * 0.2
            else:
                c["y"] += (0.0 - c["y"]) * 0.25
            if abs(c["op"] - c["op_t"]) > 0.01:
                c["op"] += (c["op_t"] - c["op"]) * 0.25
            if c["op_t"] == 0.0 and c["op"] < 0.05:
                self.chars.remove(c)
        self.update()
    def paintEvent(self, e):
        p = QPainter(self)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setClipRect(self.rect())
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor("#2F3033"))
        p.drawRoundedRect(self.rect(), 22, 22)
        fm = QFontMetrics(self.font())
        cx = 15.0
        for c in self.chars:
            p.setOpacity(min(1.0, max(0.0, c["op"])))
            p.setPen(QColor("#E2E2E5"))
            p.drawText(int(c["x"]), int(self.height()/2 + fm.descent() + 3 + c["y"]), c["c"])
            if not c.get("d"):
                cx = max(cx, c["x"] + fm.horizontalAdvance(c["c"]))
        if self.hasFocus():
            p.setOpacity((math.sin(self.c_blink) + 1.0) / 2.0)
            p.drawRect(int(cx) + 2, int(self.height()/2 - fm.ascent() + 3), 2, fm.height())

class App(QWidget):
    def __init__(self):
        super().__init__()
        try:
            with open(cfg_f) as f:
                self.state = json.load(f)
        except Exception:
            self.state = {"muted": False, "preset": 0, "volume": 100, "mouse": True, "headset": False}
        try:
            with open(cust_f) as f:
                self.cust = json.load(f)
        except Exception:
            self.cust = {}
        self.init_ui()
    def init_ui(self):
        self.setWindowTitle("Hyprkey")
        self.setFixedWidth(278)
        self.setStyleSheet("background-color: #1A1C1E; font-family: sans-serif;")
        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignHCenter)
        layout.setSpacing(16)
        layout.setContentsMargins(34, 26, 34, 26)
        self.title = QLabel("HYPRKEY")
        self.title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        tf = QFont("Arial Black")
        tf.setFamilies(["Monument Extended", "Syne", "Cabinet Grotesk", "Haettenschweiler", "Impact", "Arial Black", "sans-serif"])
        tf.setBold(True)
        tf.setWeight(QFont.Weight.Black)
        tf.setStretch(125)
        tf.setLetterSpacing(QFont.SpacingType.AbsoluteSpacing, 4.0)
        tf.setPixelSize(30)
        self.title.setFont(tf)
        self.title.setStyleSheet("color: #FFFFFF; font-weight: 900; letter-spacing: 4px; padding-bottom: 2px;")
        layout.addWidget(self.title)
        top_layout = QHBoxLayout()
        top_layout.setSpacing(15)
        self.pwr_btn = QPushButton("⏻")
        self.pwr_btn.setFixedSize(64, 64)
        self.pwr_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.pwr_btn.clicked.connect(self.toggle_mute)
        self.mbtn = MBtn()
        self.mbtn.setFixedSize(131, 64)
        self.mbtn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.mbtn.clicked.connect(self.toggle_mouse)
        top_layout.addWidget(self.pwr_btn)
        top_layout.addWidget(self.mbtn)
        layout.addLayout(top_layout)
        self.hbtn = HBtn()
        self.hbtn.setFixedSize(210, 38)
        self.hbtn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.hbtn.clicked.connect(self.toggle_headset)
        layout.addWidget(self.hbtn, alignment=Qt.AlignmentFlag.AlignCenter)
        self.combo = QComboBox()
        self.combo.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.combo.setFixedSize(210, 44)
        self.combo.addItems(PRESETS)
        self.combo.setCurrentIndex(self.state.get("preset", 0) if self.state.get("preset", 0) < len(PRESETS) else 0)
        self.combo.currentIndexChanged.connect(self.change_preset)
        self.combo.setStyleSheet("QComboBox { background-color: #2F3033; color: #E2E2E5; border-radius: 22px; padding-left: 20px; font-size: 13px; font-weight: bold; border: none; } QComboBox::drop-down { border: none; width: 40px; } QComboBox QAbstractItemView { background-color: #2F3033; color: #E2E2E5; selection-background-color: #E2E2E5; selection-color: #1A1C1E; border-radius: 12px; outline: none; padding: 5px; }")
        layout.addWidget(self.combo, alignment=Qt.AlignmentFlag.AlignCenter)
        sl_box = QHBoxLayout()
        sl_box.setSpacing(10)
        self.vicon = VIcon()
        self.vol_sl = QSlider(Qt.Orientation.Horizontal)
        self.vol_sl.setRange(0, 100)
        self.vol_sl.setValue(int(self.state.get("volume", 100)))
        self.vol_sl.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self.vol_sl.setStyleSheet("QSlider { min-height: 22px; } QSlider::groove:horizontal { border-radius: 4px; height: 8px; background: #2F3033; } QSlider::sub-page:horizontal { background: #E2E2E5; border-radius: 4px; } QSlider::handle:horizontal { background: #E2E2E5; width: 16px; height: 16px; margin: -4px 0; border-radius: 8px; }")
        self.vol_sl.valueChanged.connect(self.change_vol)
        sl_box.addWidget(self.vicon)
        sl_box.addWidget(self.vol_sl)
        layout.addLayout(sl_box)
        self.test_box = JText()
        fnt = self.test_box.font()
        fnt.setPointSize(12)
        fnt.setBold(True)
        self.test_box.setFont(fnt)
        layout.addWidget(self.test_box, alignment=Qt.AlignmentFlag.AlignCenter)
        self.cpanel = QFrame()
        self.cpanel.setStyleSheet("QFrame { border: none; }")
        cl = QVBoxLayout(self.cpanel)
        cl.setContentsMargins(0, 4, 0, 4)
        cl.setSpacing(6)
        def make_sl(name, minv, maxv, val, cb):
            r = QHBoxLayout()
            r.setContentsMargins(2, 0, 2, 0)
            r.setSpacing(8)
            l = QLabel(name)
            l.setFixedWidth(36)
            l.setStyleSheet("color:#A0A0A5; font-size:11px; font-weight:bold;")
            s = QSlider(Qt.Orientation.Horizontal)
            s.setRange(minv, maxv)
            s.setValue(int(val))
            s.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
            s.setStyleSheet("QSlider { min-height: 22px; } QSlider::groove:horizontal { border-radius: 3px; height: 6px; background: #2F3033; } QSlider::sub-page:horizontal { background: #A0A0A5; border-radius: 3px; } QSlider::handle:horizontal { background: #A0A0A5; width: 14px; height: 14px; margin: -4px 0; border-radius: 7px; }")
            s.valueChanged.connect(cb)
            r.addWidget(l)
            r.addWidget(s)
            cl.addLayout(r)
            return s
        self.sf = make_sl("Freq", 100, 1000, self.cust.get("freq", 380), self.save_c)
        self.sc = make_sl("Click", 0, 50, self.cust.get("click", 2), self.save_c)
        self.sw = make_sl("Warm", 0, 100, self.cust.get("warm", 35), self.save_c)
        self.sd = make_sl("Decay", 10, 200, self.cust.get("decay", 75), self.save_c)
        self.sp = make_sl("Drop", 0, 100, self.cust.get("drop", 30), self.save_c)
        self.su = make_sl("Dur", 15, 80, self.cust.get("dur", 35), self.save_c)
        self.st = make_sl("Soft", 5, 50, self.cust.get("soft", 20), self.save_c)
        self.sb = make_sl("Body", 0, 100, self.cust.get("body", 30), self.save_c)
        layout.addWidget(self.cpanel)
        self.anim = QVariantAnimation(self)
        self.anim.setDuration(280)
        self.anim.valueChanged.connect(self.on_anim_step)
        self.update_ui()
        self.check_cpanel(False)
    def on_anim_step(self, val):
        self.cpanel.setFixedHeight(val)
        self.adjustSize()
    def toggle_mute(self):
        self.state["muted"] = not self.state["muted"]
        self.save_cfg()
        self.update_ui()
    def toggle_mouse(self):
        self.state["mouse"] = not self.state.get("mouse", True)
        self.save_cfg()
        self.update_ui()
    def toggle_headset(self):
        self.state["headset"] = not self.state.get("headset", False)
        self.save_cfg()
        self.update_ui()
    def change_preset(self, idx):
        self.state["preset"] = idx
        self.save_cfg()
        self.check_cpanel(True)
    def change_vol(self, val):
        self.state["volume"] = int(val)
        self.save_cfg()
    def save_c(self):
        self.cust = {"freq": int(self.sf.value()), "click": int(self.sc.value()), "warm": int(self.sw.value()), "decay": int(self.sd.value()), "drop": int(self.sp.value()), "dur": int(self.su.value()), "soft": int(self.st.value()), "body": int(self.sb.value())}
        with open(cust_f, "w") as f:
            json.dump(self.cust, f)
        self.save_cfg()
    def save_cfg(self):
        with open(cfg_f, "w") as f:
            json.dump(self.state, f)
        try:
            with open(pid_f) as f:
                os.kill(int(f.read().strip()), signal.SIGUSR1)
        except Exception:
            pass
    def check_cpanel(self, animate=False):
        is_cust = (self.state.get("preset", 0) == len(PRESETS) - 1)
        target = 248 if is_cust else 0
        if animate:
            self.anim.setStartValue(self.cpanel.height())
            self.anim.setEndValue(target)
            self.anim.start()
        else:
            self.cpanel.setFixedHeight(target)
            self.adjustSize()
    def update_ui(self):
        if self.state["muted"]:
            self.pwr_btn.setStyleSheet("QPushButton { background-color: #2F3033; color: #74777F; border-radius: 32px; font-size: 28px; font-weight: bold; border: none; }")
        else:
            self.pwr_btn.setStyleSheet("QPushButton { background-color: #E2E2E5; color: #1A1C1E; border-radius: 32px; font-size: 28px; font-weight: bold; border: none; }")
        m_on = self.state.get("mouse", True)
        self.mbtn.on = m_on
        self.mbtn.setStyleSheet(f"QPushButton {{ background-color: {'#E2E2E5' if m_on else '#2F3033'}; border-top-left-radius: 14px; border-bottom-left-radius: 14px; border-top-right-radius: 32px; border-bottom-right-radius: 32px; border: none; }}")
        self.mbtn.update()
        h_on = self.state.get("headset", False)
        self.hbtn.on = h_on
        self.hbtn.setStyleSheet(f"QPushButton {{ background-color: {'#E2E2E5' if h_on else '#2F3033'}; border-radius: 19px; border: none; }}")
        self.hbtn.update()

if __name__ == "__main__":
    app = QApplication(sys.argv)
    win = App()
    win.show()
    sys.exit(app.exec())
EOF

cat << EOF > "$BIN_DIR/hyprkey"
#!/usr/bin/env bash
pkill -9 -f "daemon.py" >/dev/null 2>&1 || true
nohup "$VENV_DIR/bin/python3" "$APP_DIR/daemon.py" >/dev/null 2>&1 &
"$VENV_DIR/bin/python3" "$APP_DIR/gui.py"
EOF

cat << EOF > "$DESKTOP_DIR/hyprkey.desktop"
[Desktop Entry]
Name=Hyprkey
Comment=Relaxing ASMR Keyboard Sound Generator
Exec=$BIN_DIR/hyprkey
Terminal=false
Type=Application
Categories=Utility;Audio;
EOF

chmod +x "$APP_DIR/daemon.py" "$APP_DIR/gui.py" "$BIN_DIR/hyprkey"

echo "==> [4/4] Запуск приложения..."
"$BIN_DIR/hyprkey"
