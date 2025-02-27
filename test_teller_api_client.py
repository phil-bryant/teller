from teller_api_client_type import TellerAPIClient

class TestTellerAPIClient(TellerAPIClient):
    def __init__(self, test_response=None):
        self.test_response = test_response or {"test": "data"}
    
    def get(self, path, params=None):
        print(f"TestTellerAPIClient.get(path={path}, params={params})")
        return self.test_response 