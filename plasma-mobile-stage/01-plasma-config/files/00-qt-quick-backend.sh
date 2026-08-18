# TypixDeck: Plasma Mobile 6 is known to have rendering problems on the
# Raspberry Pi KMS/V3D driver (e.g. black screen in the task switcher when
# using OpenGL). Default to the Qt Quick software rasterizer as a conservative
# fallback so the UI is usable out of the box.
#
# To switch back to GPU (OpenGL/RHI) rendering, either delete this file or
# override the variable from a user-level script in
# ~/.config/plasma-workspace/env/ (user scripts are sourced after the
# system-wide ones in /etc/xdg/plasma-workspace/env/), e.g.:
#   export QT_QUICK_BACKEND=rhi
#
# This file only affects Plasma sessions: startplasma sources *.sh files from
# plasma-workspace/env/ at session startup, so other sessions and the SDDM
# greeter are not touched.
export QT_QUICK_BACKEND=software
