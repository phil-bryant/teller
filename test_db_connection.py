from teller_db_client import TellerDBClient

def test_connection():
    client = TellerDBClient()
    connected = client.connect()
    print(f"Connection successful: {connected}")
    
    if connected:
        tables = client.get_tables()
        print(f"Available tables: {tables}")

if __name__ == "__main__":
    test_connection() 