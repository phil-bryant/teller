from typing import Dict, List

class TellerAccount:
    def __init__(self, account_data: dict, api_client=None):
        self.api_client = api_client
        self.id = account_data["id"]
        self.enrollment_id = account_data["enrollment_id"]
        self.institution = account_data["institution"]
        self.name = account_data["name"]
        self.type = account_data["type"]
        self.subtype = account_data["subtype"]
        self.currency = account_data["currency"]
        self.last_four = account_data["last_four"]
        self.status = account_data["status"]
        self.links = account_data["links"]
        self._available_balance = None
    
    @property
    def available_balance(self) -> str:
        if self._available_balance is None:
            balances = self.get_balances()
            self._available_balance = balances.get('available', '0.00')
        return self._available_balance
    
    @property
    def institution_name(self) -> str:
        return self.institution["name"]
    
    @property
    def self_link(self) -> str:
        return self.links["self"]
    
    @property
    def balances_link(self) -> str:
        return self.links["balances"]
    
    @property
    def transactions_link(self) -> str:
        return self.links["transactions"]
    
    def get_balances(self) -> Dict:
        return self.api_client.get(self.balances_link)
    
    def get_transactions(self, count: int = None) -> List[Dict]:
        params = {}
        if count: params['count'] = count
        return self.api_client.get(self.transactions_link, params)    
    
    def __str__(self):
        return f"{self.institution_name} {self.name} ({self.subtype}) {self.last_four}" 