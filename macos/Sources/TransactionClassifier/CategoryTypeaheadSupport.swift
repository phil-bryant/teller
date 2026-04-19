import Foundation

struct CategoryTypeaheadOption: Equatable, Identifiable {
    let categoryId: Int?
    let label: String
    var id: String { categoryId.map { "cat-\($0)" } ?? "none" }
}

func rankedCategoryOptions(query: String, categories: [CategoryOption]) -> [CategoryTypeaheadOption] {
    let normalizedQuery = normalizeSearchText(query)
    let noneOption = CategoryTypeaheadOption(categoryId: nil, label: "No category")
    if normalizedQuery.isEmpty {
        let categoryOptions = categories.map { CategoryTypeaheadOption(categoryId: $0.nys_snw_category_id, label: $0.display_label) }
        return [noneOption] + categoryOptions
    }
    let ranked = categories.enumerated().compactMap { index, category -> (Int, Int, CategoryTypeaheadOption)? in
        guard let score = fuzzyCategoryScore(label: category.display_label, query: normalizedQuery) else { return nil }
        let option = CategoryTypeaheadOption(categoryId: category.nys_snw_category_id, label: category.display_label)
        return (score, index, option)
    }.sorted {
        if $0.0 != $1.0 { return $0.0 > $1.0 }
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        return $0.2.label.localizedCaseInsensitiveCompare($1.2.label) == .orderedAscending
    }.map(\.2)
    return [noneOption] + ranked
}

private func fuzzyCategoryScore(label: String, query: String) -> Int? {
    let normalizedLabel = normalizeSearchText(label)
    if normalizedLabel == query { return 1000 }
    if normalizedLabel.hasPrefix(query) { return 900 - min(100, normalizedLabel.count - query.count) }
    let words = normalizedLabel.split(separator: " ")
    if let index = words.firstIndex(where: { $0.hasPrefix(query) }) { return 820 - index }
    if let range = normalizedLabel.range(of: query) {
        let prefixDistance = normalizedLabel.distance(from: normalizedLabel.startIndex, to: range.lowerBound)
        return 700 - min(200, prefixDistance)
    }
    guard let gaps = subsequenceGaps(query: query, text: normalizedLabel) else { return nil }
    return 600 - min(250, gaps)
}

private func normalizeSearchText(_ raw: String) -> String {
    raw.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func subsequenceGaps(query: String, text: String) -> Int? {
    var textIndex = text.startIndex, firstMatch: Int?, lastMatch = 0, queryCount = 0
    for queryChar in query {
        guard let match = text[textIndex...].firstIndex(of: queryChar) else { return nil }
        let offset = text.distance(from: text.startIndex, to: match)
        if firstMatch == nil { firstMatch = offset }
        lastMatch = offset
        queryCount += 1
        textIndex = text.index(after: match)
    }
    guard let start = firstMatch else { return nil }
    return max(0, (lastMatch - start + 1) - queryCount)
}
