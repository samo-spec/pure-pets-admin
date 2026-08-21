#!/usr/bin/env python3
from pathlib import Path

path = Path("PurePetsAdmin/Features/CommandCenter/AdminCommandCenterScreen.swift")
source = path.read_text(encoding="utf-8")
source = source.replace(
    "//  World-class, high-density operational command center built with Pure Pets\n"
    "//  NextGen V6 design language. Features glassmorphism materials, living ambient\n"
    "//  depth, reactive status telemetry, dynamic priority dominance hierarchy,\n"
    "//  and full RTL/LTR & VoiceOver accessibility.\n",
    "//  Priority Handoff operational surface built with the shared Pure Pets V6\n"
    "//  semantic design system, explicit state communication, and bounded hierarchy.\n"
    "//  RTL/LTR, Dynamic Type, VoiceOver, and Reduce Motion remain first-class.\n"
)
path.write_text(source, encoding="utf-8")
print("Normalized Command Center V6 header")
