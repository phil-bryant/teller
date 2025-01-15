CREATE TABLE teller.transaction_links (
COMMENT ON TABLE teller.transaction_links IS 'Links associated with transactions';
COMMENT ON COLUMN teller.transaction_links.self_link IS 'A self link to the transaction. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000/transactions/txn_oiluj93igokseo0i3a000';
COMMENT ON COLUMN teller.transaction_links.account_link IS 'A link to the account that the transaction belongs to. e.g., https://api.teller.io/accounts/acc_oiin624kqjrg2mp2ea000'; 
