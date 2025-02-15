from requests import Session

class API(Session):
    def __init__(self, base_url: str, auth_token: str, cert_pk_tuple: tuple[str, str], endpoints: dict):
        super().__init__()
        self.auth = auth_token
        self.cert = cert_pk_tuple
        self.headers = {"Accept": "application/json", "Content-Type": "application/json"}
        self.adapters.pop('http://')
        self.base_url = base_url
        self.endpoints = endpoints

    def request(self, method, endpoint, params: dict = None) -> APIObject[]:
        return self.endpoints[endpoint](super().request(method, self.base_url + endpoint, params))
