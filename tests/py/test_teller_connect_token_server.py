import unittest
import teller.teller_connect_token_server as t


class ConnectTokenServerTests(unittest.TestCase):
    def test_empty_contexts_renders_empty_state(self):
        #R075
        html = t.render_contexts_html([])
        self.assertIn("No local enrollment contexts", html)
        self.assertIn("Known Local Enrollments", html)

    def test_contexts_table_shows_institution_id_column(self):
        #R075
        rows = [
            {
                "key": "k1",
                "enrollment_id": "e1",
                "institution_id": "ins_1",
            }
        ]
        html = t.render_contexts_html(rows)
        self.assertIn("ins_1", html)
        self.assertIn("institution_id", html)

    def test_manage_mode_adds_enrollment_action(self):
        #R080
        html = t.build_html("app", "development", "", "manage", [])
        self.assertIn("Add Enrollment", html)
        self.assertIn("startAdd", html)

    def test_manage_mode_includes_reconnect_in_context_script(self):
        #R080
        html = t.build_html("app", "development", "", "manage", [
            {"key": "a", "enrollment_id": "e", "institution_id": "i"},
        ])
        self.assertIn("startReconnect", html)
        self.assertIn("deleteContext", html)


if __name__ == "__main__":
    unittest.main()
