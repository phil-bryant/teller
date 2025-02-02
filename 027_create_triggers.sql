CREATE OR REPLACE FUNCTION teller.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Core tables
CREATE TRIGGER update_institutions_updated_at
    BEFORE UPDATE ON teller.institutions
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_account_updated_at
    BEFORE UPDATE ON teller.account
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_account_details_updated_at
    BEFORE UPDATE ON teller.account_details
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_balances_updated_at
    BEFORE UPDATE ON teller.balances
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

-- Identity related tables
CREATE TRIGGER update_identity_updated_at
    BEFORE UPDATE ON teller.identity
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_address_updated_at
    BEFORE UPDATE ON teller.address
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_address_data_updated_at
    BEFORE UPDATE ON teller.address_data
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_name_updated_at
    BEFORE UPDATE ON teller.name
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_phone_number_updated_at
    BEFORE UPDATE ON teller.phone_number
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_email_updated_at
    BEFORE UPDATE ON teller.email
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

-- Transaction related tables
CREATE TRIGGER update_transaction_updated_at
    BEFORE UPDATE ON teller.transaction
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_transaction_counterparty_updated_at
    BEFORE UPDATE ON teller.transaction_counterparty
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_transaction_details_updated_at
    BEFORE UPDATE ON teller.transaction_details
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

-- Links tables
CREATE TRIGGER update_account_links_updated_at
    BEFORE UPDATE ON teller.account_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_account_details_links_updated_at
    BEFORE UPDATE ON teller.account_details_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_account_balances_links_updated_at
    BEFORE UPDATE ON teller.account_balances_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_transaction_links_updated_at
    BEFORE UPDATE ON teller.transaction_links
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at(); 