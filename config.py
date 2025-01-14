from pathlib import Path
import os

TELLER_HOME = Path(os.path.expanduser('~/.teller'))

def load_credentials():
    app_id = (TELLER_HOME / 'application_id.txt').read_text().strip()
    cert = (TELLER_HOME / 'certificate.pem').read_text()
    private_key = (TELLER_HOME / 'private_key.pem').read_text()
    return {
        'application_id': app_id,
        'cert': cert,
        'private_key': private_key
    } 