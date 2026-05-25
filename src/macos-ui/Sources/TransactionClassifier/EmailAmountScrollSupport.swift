import Foundation

private let emailAmountCurrencyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.maximumFractionDigits = 2
    return formatter
}()

private let emailAmountDecimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.usesGroupingSeparator = true
    return formatter
}()

private let emailAmountPlainDecimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.usesGroupingSeparator = false
    return formatter
}()

private let amountTotalKeywordPattern: NSRegularExpression = {
    guard let regex = try? NSRegularExpression(
        pattern: #"\b(total|order total|grand total|amount due)\b"#,
        options: [.caseInsensitive]
    ) else {
        preconditionFailure("amountTotalKeywordPattern is invalid")
    }
    return regex
}()

func amountSearchVariants(for amount: Decimal) -> [String] {
    let absAmount = amount < 0 ? -amount : amount
    let nsAmount = absAmount as NSDecimalNumber
    var variants = Set<String>()

    if let currency = emailAmountCurrencyFormatter.string(from: nsAmount) {
        variants.insert(currency)
        variants.insert("(\(currency))")
        variants.insert("-\(currency)")
    }
    if let decimal = emailAmountDecimalFormatter.string(from: nsAmount) {
        variants.insert(decimal)
    }
    if let plain = emailAmountPlainDecimalFormatter.string(from: nsAmount) {
        variants.insert(plain)
    }

    return variants.sorted { $0.count > $1.count }
}

func bestTextLineIndexForAmount(in text: String, amount: Decimal) -> Int? {
    let variants = amountSearchVariants(for: amount)
    let lines = text.components(separatedBy: .newlines)
    var matchingIndices: [Int] = []
    for (index, line) in lines.enumerated() where variants.contains(where: { line.contains($0) }) {
        matchingIndices.append(index)
    }
    guard !matchingIndices.isEmpty else { return nil }

    for index in matchingIndices.reversed() {
        let line = lines[index]
        let range = NSRange(line.startIndex..., in: line)
        if amountTotalKeywordPattern.firstMatch(in: line, range: range) != nil {
            return index
        }
    }
    return matchingIndices.last
}

func scrollToAmountJavaScript(variants: [String]) -> String? {
    guard !variants.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: variants),
          let json = String(data: data, encoding: .utf8) else {
        return nil
    }
    return """
    (function() {
      const patterns = \(json);
      const totalRe = /\\b(total|order total|grand total|amount due)\\b/i;
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      const matches = [];
      while (walker.nextNode()) {
        const node = walker.currentNode;
        const text = node.textContent || '';
        for (const p of patterns) {
          if (text.includes(p)) {
            matches.push(node.parentElement);
            break;
          }
        }
      }
      if (!matches.length) return;
      let target = matches[matches.length - 1];
      for (let i = matches.length - 1; i >= 0; i--) {
        const ctx = matches[i]?.innerText || '';
        if (totalRe.test(ctx)) { target = matches[i]; break; }
      }
      target?.scrollIntoView({ block: 'center', inline: 'center' });
    })();
    """
}

func wrappedEmailHTML(_ htmlBody: String) -> String {
    """
    <!doctype html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        html, body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.4; margin: 12px; color: -apple-system-label; background: transparent; }
        img { max-width: 100%; height: auto; }
        blockquote { border-left: 3px solid rgba(127,127,127,0.4); margin: 0; padding-left: 10px; color: -apple-system-secondary-label; }
        a { color: -apple-system-blue; }
        pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    </style></head><body>
    \(htmlBody)
    </body></html>
    """
}
