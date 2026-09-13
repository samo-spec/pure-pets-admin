from pathlib import Path

p = Path("PurePetsAdmin/Features/POS/POSHistoryView.swift")
text = p.read_text()
old = """                            Text(verbatim: String(
                                format: lineFullyRefunded
                                    ? Language.get("POS_Refund_ItemFullyRefunded", alter: "%d مسترد • مكتمل")
                                    : Language.get("POS_Refund_ItemProgress", alter: "%d مسترد • %d متبقي"),
                                item.refundedQuantity,
                                remainingQuantity
                            ))
"""
new = """                            let progressText = lineFullyRefunded
                                ? String(
                                    format: Language.get("POS_Refund_ItemFullyRefunded", alter: "%d مسترد • مكتمل"),
                                    item.refundedQuantity
                                )
                                : String(
                                    format: Language.get("POS_Refund_ItemProgress", alter: "%d مسترد • %d متبقي"),
                                    item.refundedQuantity,
                                    remainingQuantity
                                )
                            Text(verbatim: progressText)
"""
if text.count(old) != 1:
    raise SystemExit(f"Expected one progress formatter block, found {text.count(old)}")
p.write_text(text.replace(old, new, 1))
