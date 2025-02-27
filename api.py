from requests import Session, Response
from urllib.parse import urlparse
from url_merge import merge_urls

class API(Session):
    def __init__(self, base_url: str, auth_tuple: tuple[str, str], cert_pk_tuple: tuple[str, str]) -> None:
        super().__init__()
        self.auth = auth_tuple
        self.cert = cert_pk_tuple
        self.headers = {"Accept": "application/json", "Content-Type": "application/json"}
        self.adapters.pop('http://')
        self.base_url = base_url

    def request(self, method, path, params: dict = None) -> Response:
        return super().request(method, merge_urls(self.base_url, path), params)