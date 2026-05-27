import Foundation

/// JSON response bodies used by `APIClientTests`. Held in a sibling file with
/// no Swift function declarations so the JSON braces inside the multi-line
/// string literals do not confuse Lizard's heuristic Swift parser when it
/// measures function lengths in `APIClientTests.swift`.
enum APIClientTestFixtures {
    static let petsCreatedJSON: String = """
    {"nys_snw_category_id":300,"level_1":null,"level_1_name":null,"level_2":null,"level_2_name":null,"level_3":null,"level_4":null,"categorization":"Pets","applicability":null,"display_label":"Pets"}
    """

    static let petsUpdatedJSON: String = """
    {"nys_snw_category_id":300,"level_1":null,"level_1_name":null,"level_2":null,"level_2_name":null,"level_3":null,"level_4":null,"categorization":"Pets Updated","applicability":null,"display_label":"Pets Updated"}
    """

    static let petsDeletedJSON: String = """
    {"nys_snw_category_id":300,"deleted":true}
    """
}
