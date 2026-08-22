-- 0003_chats.sql
--
-- Chat, messaging, and moderation tables.

-- Chats: one thread per (listing, buyer) pair.
CREATE TABLE chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
    buyer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT unique_thread UNIQUE (listing_id, buyer_id)
);
CREATE INDEX idx_chats_buyer ON chats(buyer_id, last_message_at DESC);
CREATE INDEX idx_chats_seller ON chats(seller_id, last_message_at DESC);

-- Messages: individual chat messages with delivery tracking.
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_chat ON messages(chat_id, created_at);
CREATE INDEX idx_messages_undelivered ON messages(chat_id) WHERE delivered_at IS NULL;

-- Reports: user-submitted flags for listings or other users.
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id UUID REFERENCES listings(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed', 'dismissed')),

    CONSTRAINT report_target CHECK (listing_id IS NOT NULL OR reported_user_id IS NOT NULL)
);
CREATE INDEX idx_reports_status ON reports(status);
