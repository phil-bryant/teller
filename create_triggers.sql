CREATE OR REPLACE FUNCTION teller.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_account_updated_at
    BEFORE UPDATE ON teller.account
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();

CREATE TRIGGER update_institution_updated_at
    BEFORE UPDATE ON teller.institution
    FOR EACH ROW
    EXECUTE FUNCTION teller.update_updated_at();