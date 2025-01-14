from fastapi import FastAPI, Request
from fastapi.templating import Jinja2Templates
from pathlib import Path
from config import load_credentials, TELLER_HOME
import httpx
import webbrowser
import threading
import time
import json
from typing import Dict
from pydantic import BaseModel

class TokenRequest(BaseModel):
    token: str

app = FastAPI()
templates = Jinja2Templates(directory='templates')
TOKENS_FILE = TELLER_HOME / 'tokens.json'

# Load credentials once at startup
credentials = load_credentials()
CERT_PATH = TELLER_HOME / 'certificate.pem'
KEY_PATH = TELLER_HOME / 'private_key.pem'

def load_tokens() -> Dict[str, str]:
    if TOKENS_FILE.exists():
        return json.loads(TOKENS_FILE.read_text())
    return {}

def save_token(token: str):
    tokens = load_tokens()
    tokens['current'] = token
    TOKENS_FILE.write_text(json.dumps(tokens))
    TOKENS_FILE.chmod(0o400)

def open_browser():
    time.sleep(1.5)
    webbrowser.open('https://localhost:8443')

@app.on_event('startup')
async def startup_event():
    threading.Thread(target=open_browser, daemon=True).start()

@app.get('/')
async def home(request: Request):
    return templates.TemplateResponse('index.html', {
        'request': request,
        'application_id': credentials['application_id']
    })

@app.post('/api/store-token')
async def store_token(request: TokenRequest):
    save_token(request.token)
    return {'status': 'success'}

@app.get('/api/accounts')
async def get_accounts(access_token: str):
    async with httpx.AsyncClient(
        cert=(str(CERT_PATH), str(KEY_PATH)),
        verify=True
    ) as client:
        response = await client.get(
            'https://api.teller.io/accounts',
            headers={'Authorization': f'Bearer {access_token}'}
        )
        return response.json() 