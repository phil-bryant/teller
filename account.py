class Account:
    def __init__(self, account_data: dict):
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
    
    def __str__(self):
        return f"{self.name} ({self.type}/{self.subtype}) - {self.institution_name} *{self.last_four}" 