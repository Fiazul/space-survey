from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/reference/stellar-structure-review"
PANELS = [
    ("main-sequence", "MAIN SEQUENCE / UV-INSPIRED CORONA", "Gold sensor palette; visible-light variant supplied separately."),
    ("red-giant", "RED GIANT / CONVECTION", "Broad convection and diffuse envelope."),
    ("white-dwarf-disk", "WHITE DWARF / DEBRIS DISK", "Optional disk-bearing variant; compact central star."),
    ("pulsar-wind", "PULSAR / WIND NEBULA", "Vela-inspired X-ray palette; compressed structure scale."),
    ("red-dwarf", "RED DWARF / MAGNETIC ACTIVITY", "Enhanced magnetic network and clustered plasma strands."),
    ("brown-dwarf", "BROWN DWARF / CLOUDS + AURORA", "Uneven belts and aurora variant; enhanced brightness."),
]


def panel(ax, path, title, note):
    ax.imshow(Image.open(path))
    ax.set_axis_off()
    ax.set_title(title, color="#cee0ee", loc="left", fontsize=11, pad=12)
    ax.text(0.0, -0.04, note, transform=ax.transAxes, color="#9badbb", fontsize=8)


fig, axes = plt.subplots(2, 3, figsize=(18, 10.8), facecolor="#05080c")
fig.suptitle("ASTRYX / STELLAR STRUCTURE REVIEW 02", x=0.045, ha="left", color="#edf3f8", fontsize=21)
fig.subplots_adjust(left=0.03, right=0.98, top=0.89, bottom=0.07, wspace=0.08, hspace=0.24)
for ax, (slug, title, note) in zip(axes.flat, PANELS):
    panel(ax, OUT / f"{slug}.png", title, note)
fig.text(0.045, 0.025, "Actual Godot renders of proposed materials and 3D geometry. Preview only; gameplay unchanged.", color="#9badbb", fontsize=11)
fig.savefig(OUT / "comparison-02.png", dpi=140, facecolor=fig.get_facecolor())
plt.close(fig)

reference = Path("/home/fiazul/Downloads/brown_dwarf-1.jpeg")
if reference.exists():
    fig, axes = plt.subplots(1, 3, figsize=(18, 5.4), facecolor="#05080c")
    fig.suptitle("BROWN DWARF / REFERENCE AND PREVIEW", x=0.04, ha="left", color="#edf3f8", fontsize=20)
    fig.subplots_adjust(left=0.025, right=0.98, top=0.84, bottom=0.10, wspace=0.06)
    panel(axes[0], reference, "YOUR REFERENCE", "NASA artist concept / Chuck Carter and Gregg Hallinan, Caltech.")
    panel(axes[1], ROOT / "docs/reference/star-family-review/warm-l-dwarf.png", "PREVIOUS PREVIEW", "Regular high-contrast stripes; no auroral structure.")
    panel(axes[2], OUT / "brown-dwarf.png", "REVISED GODOT PREVIEW", "Sheared cloud streaks, uneven belts, darker red and a polar curtain.")
    fig.savefig(OUT / "brown-dwarf-comparison.png", dpi=140, facecolor=fig.get_facecolor())
    plt.close(fig)

print(f"Stellar review sheets saved to {OUT}")
