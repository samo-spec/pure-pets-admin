from pathlib import Path

p = Path("PurePetsAdmin/Features/POS/POSHistoryView.swift")
text = p.read_text()

marker = """    private var refundDisabled: Bool {
        isCancelled || (isFullyRefunded && !routesToLivePetReturn)
    }
"""
addition = marker + """
    private var refundActionTitle: String {
        if routesToLivePetReturn {
            return isRefunded && !isFullyRefunded
                ? Language.get("LivePet_Action_ReturnAnother", alter: "استرجاع حيوان آخر")
                : Language.get("LivePet_Action_Return", alter: "استرجاع الحيوان")
        }
        return isRefunded && !isFullyRefunded
            ? Language.get("POS_Action_AdditionalRefund", alter: "استرداد عنصر آخر")
            : Language.get("POS_Action_Refund", alter: "استرداد")
    }
"""
if text.count(marker) != 2:
    raise SystemExit(f"Expected 2 refundDisabled blocks, got {text.count(marker)}")
text = text.replace(marker, addition)

old_title = 'Text(routesToLivePetReturn ? Language.get("LivePet_Action_Return", alter: "استرجاع الحيوان") : Language.get("POS_Action_Refund", alter: "استرداد"))'
if text.count(old_title) != 2:
    raise SystemExit(f"Expected 2 refund CTA titles, got {text.count(old_title)}")
text = text.replace(old_title, "Text(refundActionTitle)")

old_progress = """                        if item.refundedQuantity > 0 {
                            Text(verbatim: "(\\(item.refundedQuantity.englishDigits) \\(Language.get(\"POS_Status_Refunded\", alter: \"مسترد\")))")
                                .font(DossierFont.bold(10, relativeTo: .caption2))
                                .foregroundColor(Color(uiColor: .systemOrange))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemOrange).opacity(0.12), in: Capsule())
                        }
"""
new_progress = """                        if item.refundedQuantity > 0 {
                            let remainingQuantity = max(0, item.quantity - item.refundedQuantity)
                            let lineFullyRefunded = remainingQuantity == 0
                            let progressColor = lineFullyRefunded ? Color(uiColor: .systemGreen) : Color(uiColor: .systemOrange)
                            Text(verbatim: String(
                                format: lineFullyRefunded
                                    ? Language.get("POS_Refund_ItemFullyRefunded", alter: "%d مسترد • مكتمل")
                                    : Language.get("POS_Refund_ItemProgress", alter: "%d مسترد • %d متبقي"),
                                item.refundedQuantity,
                                remainingQuantity
                            ))
                                .font(DossierFont.bold(10, relativeTo: .caption2))
                                .foregroundColor(progressColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(progressColor.opacity(0.12), in: Capsule())
                        }
"""
if old_progress not in text:
    raise SystemExit("Item refund progress block not found")
text = text.replace(old_progress, new_progress, 1)

old_financial = """                if effectiveRefundedAmount > 0 {
                    dossierRow(
                        label: Language.get("POS_Telemetry_Refunds", alter: "إجمالي المسترد"),
                        value: "−" + effectiveRefundedAmount.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"),
                        valueColor: Color(uiColor: .systemOrange)
                    )
                }
"""
new_financial = """                if effectiveRefundedAmount > 0 {
                    dossierRow(
                        label: Language.get("POS_Telemetry_Refunds", alter: "إجمالي المسترد"),
                        value: "−" + effectiveRefundedAmount.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"),
                        valueColor: Color(uiColor: .systemOrange)
                    )
                    dossierRow(
                        label: Language.get("POS_Refund_NetRetained", alter: "صافي قيمة البيع المتبقية"),
                        value: max(0, receipt.total - effectiveRefundedAmount).englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"),
                        valueColor: Color(uiColor: .systemBlue)
                    )
                }
"""
if old_financial not in text:
    raise SystemExit("Refund financial block not found")
text = text.replace(old_financial, new_financial, 1)
p.write_text(text)

localizations = {
    "PurePetsAdmin/en.lproj/Localizable.strings": {
        "POS_Action_AdditionalRefund": "Refund another item",
        "LivePet_Action_ReturnAnother": "Return another animal",
        "POS_Refund_ItemProgress": "%d refunded • %d remaining",
        "POS_Refund_ItemFullyRefunded": "%d refunded • complete",
        "POS_Refund_NetRetained": "Net retained",
    },
    "PurePetsAdmin/ar.lproj/Localizable.strings": {
        "POS_Action_AdditionalRefund": "استرداد عنصر آخر",
        "LivePet_Action_ReturnAnother": "استرجاع حيوان آخر",
        "POS_Refund_ItemProgress": "%d مسترد • %d متبقي",
        "POS_Refund_ItemFullyRefunded": "%d مسترد • مكتمل",
        "POS_Refund_NetRetained": "صافي قيمة البيع المتبقية",
    },
}
for path, entries in localizations.items():
    lp = Path(path)
    content = lp.read_text()
    additions = []
    for key, value in entries.items():
        if f'"{key}"' not in content:
            additions.append(f'"{key}" = "{value}";')
    if additions:
        lp.write_text(content.rstrip() + "\n\n// Post-first-refund multi-refund lifecycle\n" + "\n".join(additions) + "\n")
