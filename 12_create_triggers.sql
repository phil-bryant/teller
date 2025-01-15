CREATE OR REPLACE FUNCTION teller.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_institutions_updated_at
    BEFORE UPDATE ON teller.institutions
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_accounts_updated_at
    BEFORE UPDATE ON teller.accounts
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_account_details_updated_at
    BEFORE UPDATE ON teller.account_details
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_account_balances_updated_at
    BEFORE UPDATE ON teller.account_balances
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_identities_updated_at
    BEFORE UPDATE ON teller.identities
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_addresses_updated_at
    BEFORE UPDATE ON teller.addresses
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_identity_addresses_updated_at
    BEFORE UPDATE ON teller.identity_addresses
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_identity_names_updated_at
    BEFORE UPDATE ON teller.identity_names
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_identity_phone_numbers_updated_at
    BEFORE UPDATE ON teller.identity_phone_numbers
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_identity_emails_updated_at
    BEFORE UPDATE ON teller.identity_emails
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_transaction_counterparties_updated_at
    BEFORE UPDATE ON teller.transaction_counterparties
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_transactions_updated_at
    BEFORE UPDATE ON teller.transactions
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at(); 