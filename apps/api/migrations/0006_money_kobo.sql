-- 0006_money_kobo.sql
--
-- Money as integer minor units (kobo) + explicit ISO 4217 currency.
--
-- Why: floats/naive integers for money drift and are ambiguous across
-- currencies. From this migration on:
--   * `price` is ALWAYS minor units (kobo for NGN). ₦1,500.00 => 150000.
--   * `currency` is an explicit ISO 4217 code so multi-currency settlement
--     is representable without another migration.
--
-- Existing rows stored whole naira; they are scaled x100 into kobo.

ALTER TABLE listings
    ALTER COLUMN price TYPE BIGINT,
    ALTER COLUMN price SET DEFAULT NULL;

-- Scale existing naira values into kobo BEFORE adding the constraint.
UPDATE listings SET price = price * 100 WHERE price IS NOT NULL;

-- Money amounts are unsigned by policy; debits are modelled explicitly.
ALTER TABLE listings
    ADD CONSTRAINT listings_price_non_negative
        CHECK (price IS NULL OR price >= 0);

ALTER TABLE listings
    ADD COLUMN currency CHAR(3) NOT NULL DEFAULT 'NGN'
        CHECK (currency ~ '^[A-Z]{3}$');

-- Price filters are frequent: (status, currency, price) helps range scans.
CREATE INDEX idx_listings_currency_price ON listings(status, currency, price);

-- Barter-only listings (price IS NULL) can carry an exchange request.
-- Length-matched to the mobile editor's validation (max 1000 chars).
ALTER TABLE listings
    ADD COLUMN barter_request TEXT
        CHECK (barter_request IS NULL OR char_length(barter_request) <= 1000);

-- At most one of price / barter_request may be set: a listing is either
-- priced or barter-only, never both and never neither.
ALTER TABLE listings
    ADD CONSTRAINT price_or_barter_exclusive
        CHECK (
            (price IS NOT NULL AND barter_request IS NULL)
            OR (price IS NULL)
        );
