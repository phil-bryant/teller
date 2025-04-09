from teller.db_client import TellerDBClient
client = TellerDBClient()

# Get column info for identity_name table
print("\n--- COLUMN INFORMATION FOR IDENTITY_NAME ---\n")
result = client._execute("SELECT column_name, unique_constraint FROM teller.column_information WHERE table_name = 'identity_name'")
for row in result:
    print(f"Column: {row['column_name']}, Unique constraint: {row['unique_constraint']}")

# Look at the raw table_constraints
print("\n--- TABLE CONSTRAINTS ---\n")
result = client._execute("""
    SELECT * FROM teller.table_constraints 
    WHERE table_name = 'identity_name' AND constraint_type = 'unique'
""")
for row in result:
    print(row) 