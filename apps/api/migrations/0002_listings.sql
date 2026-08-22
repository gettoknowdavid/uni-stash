-- 0002_listings.sql
--
-- Marketplace core: categories, listings, images, and full-text search.

-- Categories: listing classification (textbooks, electronics, etc.).
CREATE TABLE categories (
    id SMALLSERIAL PRIMARY KEY,
    slug TEXT UNIQUE NOT NULL,
    label TEXT NOT NULL,
    sort_order SMALLINT NOT NULL DEFAULT 0
);

-- Listings: the central entity of the marketplace.
CREATE TABLE listings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id SMALLINT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    price INTEGER,
    condition TEXT NOT NULL DEFAULT 'used' CHECK (condition IN ('new', 'used', 'fair')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'reserved', 'sold', 'deleted')),
    reserved_by UUID REFERENCES users(id),
    reserved_at TIMESTAMPTZ,
    search_vector TSVECTOR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT reserved_fields_consistent CHECK (
        (status = 'reserved' AND reserved_by IS NOT NULL AND reserved_at IS NOT NULL)
        OR (status != 'reserved' AND reserved_by IS NULL)
    )
);
CREATE INDEX idx_listings_status_category ON listings(status, category_id);
CREATE INDEX idx_listings_seller ON listings(seller_id);
CREATE INDEX idx_listings_search ON listings USING GIN (search_vector);

-- Full-text search: keep search_vector in sync via trigger rather than a
-- generated column, since weighting title > description needs setweight().
CREATE FUNCTION listings_search_vector_update() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_listings_search_vector
    BEFORE INSERT OR UPDATE OF title, description ON listings
    FOR EACH ROW EXECUTE FUNCTION listings_search_vector_update();

-- Images: up to 3 per listing, uploaded directly to Backblaze B2.
CREATE TABLE images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL,
    position SMALLINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT max_three_images UNIQUE (listing_id, position)
);
CREATE INDEX idx_images_listing ON images(listing_id);
