# Realtime Architecture — Uni-Stash API

> **Audience:** Mobile and frontend developers integrating with the Uni-Stash API.  
> **Last updated:** See repository history.

---

## Table of Contents

1. [Overview](#overview)
2. [Pusher Channels — Realtime Chat](#pusher-channels--realtime-chat)
   - [Setup & Configuration](#setup--configuration)
   - [Channel Naming](#channel-naming)
   - [Authentication Flow](#authentication-flow)
   - [Events Reference](#events-reference)
   - [Fallback Behavior](#fallback-behavior)
3. [Pusher Beams — Push Notifications](#pusher-beams--push-notifications)
   - [Setup & Configuration](#setup--configuration-1)
   - [Interest Naming](#interest-naming)
   - [Device Registration Flow](#device-registration-flow)
   - [Push Payload Examples](#push-payload-examples)
4. [Integration Checklist](#integration-checklist)
5. [Environment Variables Reference](#environment-variables-reference)

---

## Overview

Uni-Stash uses a **two-layer realtime strategy**:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client (App)                             │
│                                                                 │
│   ┌─────────────────────┐     ┌─────────────────────────────┐  │
│   │  Pusher Channels    │     │      Pusher Beams           │  │
│   │  (WebSocket)        │     │  (APNs / FCM / Web Push)    │  │
│   │                     │     │                             │  │
│   │  App is OPEN        │     │  App is BACKGROUND/CLOSED   │  │
│   │  Low-latency signal │     │  Background notification    │  │
│   └────────┬────────────┘     └──────────────┬──────────────┘  │
└────────────┼──────────────────────────────────┼─────────────────┘
             │  signal to re-fetch              │  push payload
             ▼                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Uni-Stash REST API                           │
│              (always the source of truth)                       │
└─────────────────────────────────────────────────────────────────┘
```

| Layer | Technology | Use Case | When Active |
|---|---|---|---|
| **Realtime events** | Pusher Channels (WebSocket) | In-app chat updates | App is open and connected |
| **Push notifications** | Pusher Beams (APNs / FCM) | Background / offline alerts | App is backgrounded or closed |

### Key Design Principles

- **Realtime events are signals, not data carriers.** When a `message.new` event arrives, the client should call the REST API to fetch the actual message content. The event payload contains only identifiers.
- **The REST API is always the source of truth.** Realtime delivery is best-effort; messages are persisted to the database regardless of whether the realtime publish succeeds.
- **Provider-agnostic architecture.** Both layers are abstracted behind traits (`RealtimePublisher`). The underlying provider (Pusher, Ably, self-hosted WebSocket, etc.) can be swapped by changing configuration — no feature code changes required.

---

## Pusher Channels — Realtime Chat

### Setup & Configuration

Set the following environment variable to enable Pusher Channels:

```
REALTIME_PROVIDER=pusher
```

If `REALTIME_PROVIDER` is absent or set to any other value, the backend uses a **NullPublisher** (no-op). Chat functionality degrades gracefully to REST polling — no errors are thrown.

The backend publishes events via Pusher's HTTP Trigger Events API:

```
POST https://api-{cluster}.pusher.com/apps/{app_id}/events
```

Requests are authenticated using an **HMAC-SHA256** signature computed over:

```
POST\n{path}\n{sorted_query_params}
```

> This is handled entirely server-side. Clients do **not** need to implement Pusher's HTTP API.

---

### Channel Naming

All chat channels are **private channels** and follow this naming convention:

```
private-{suffix}
```

| Channel | Pattern | Example |
|---|---|---|
| Chat channel | `private-chat-{chat_uuid}` | `private-chat-a1b2c3d4-e5f6-...` |
| User channel | `private-user-{user_uuid}` | `private-user-a1b2c3d4-e5f6-...` |

> ⚠️ **Build chat channel names with `chat_channel(&chat_id)`** (or literally
> `private-chat-{uuid}`). Constructing them as `private_channel(&id.to_string())`
> yields `private-{uuid}` — Pusher accepts and counts publishes to that name,
> but no client ever subscribes to it, so events silently reach nobody. The
> user channel (`private_user_channel(&user_id)`) carries `message.new` for
> messages addressed to that user in *any* chat and may only be signed by the
> account owner (enforced by `realtime/auth`).

Private channels require client-side authentication before Pusher will allow a subscription (see [Authentication Flow](#authentication-flow) below).

---

### Authentication Flow

Private channel subscriptions must be authorized by the Uni-Stash backend. The Pusher client SDK handles this automatically by calling the configured auth endpoint.

**Auth Endpoint:**

```
POST /api/v1/realtime/auth
```

**Flow:**

```
Client (Pusher SDK)          Uni-Stash API          Pusher
       │                           │                    │
       │── subscribe to ──────────►│                    │
       │   private-chat-{uuid}     │                    │
       │                           │                    │
       │◄── auth request ──────────│                    │
       │    (socket_id,            │                    │
       │     channel_name)         │                    │
       │                           │                    │
       │── POST /api/v1/ ─────────►│                    │
       │   realtime/auth           │ validate user is   │
       │   {socket_id,             │ a chat participant │
       │    channel_name}          │                    │
       │                           │                    │
       │◄── {"auth": "key:sig"} ───│                    │
       │                           │                    │
       │── present auth token ────────────────────────►│
       │                           │                    │
       │◄── subscription granted ──────────────────────│
```

**Auth Request (sent automatically by Pusher SDK):**

```http
POST /api/v1/realtime/auth
Authorization: Bearer {jwt_token}
Content-Type: application/x-www-form-urlencoded

socket_id=123456.789&channel_name=private-chat-a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

**Auth Response:**

```json
{
  "auth": "app_key:hmac_sha256_signature"
}
```

The backend validates that the authenticated user is a **participant of the requested chat** before issuing the auth token. Unauthorized subscription attempts return `403 Forbidden`.

**Client SDK Configuration Example (JavaScript):**

```javascript
import Pusher from 'pusher-js';

const pusher = new Pusher(PUSHER_APP_KEY, {
  cluster: PUSHER_CLUSTER,
  authEndpoint: 'https://api.uni-stash.com/api/v1/realtime/auth',
  auth: {
    headers: {
      Authorization: `Bearer ${userJwtToken}`,
    },
  },
});

// Subscribe to a private chat channel
const channel = pusher.subscribe(`private-chat-${chatId}`);

channel.bind('message.new', (data) => {
  // data = { type: "message_new", chat_id: "uuid" }
  // Re-fetch messages from the REST API
  fetchMessages(data.chat_id);
});

channel.bind('message.read', (data) => {
  // data = { type: "message_read", chat_id: "uuid", last_read_message_id: "uuid" }
  // Update read receipts in local state
  updateReadReceipt(data.chat_id, data.last_read_message_id);
});
```

**Client SDK Configuration Example (Flutter/Dart):**

```dart
final pusher = PusherChannelsFlutter.getInstance();

await pusher.init(
  apiKey: pusherAppKey,
  cluster: pusherCluster,
  authEndpoint: 'https://api.uni-stash.com/api/v1/realtime/auth',
  onAuthorizer: (channelName, socketId, options) async {
    final response = await http.post(
      Uri.parse('https://api.uni-stash.com/api/v1/realtime/auth'),
      headers: {
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'socket_id=$socketId&channel_name=$channelName',
    );
    return jsonDecode(response.body);
  },
);

await pusher.subscribe(
  channelName: 'private-chat-$chatId',
  onEvent: (event) {
    if (event.eventName == 'message.new') {
      final data = jsonDecode(event.data);
      fetchMessages(data['chat_id']);
    }
  },
);
```

---

### Events Reference

| Event Name | Trigger | Payload |
|---|---|---|
| `message.new` | A new message is sent in the chat | `{"type": "message_new", "chat_id": "uuid"}` |
| `message.read` | Messages are marked as read | `{"type": "message_read", "chat_id": "uuid", "last_read_message_id": "uuid"}` |

**`message.new` Payload:**

```json
{
  "type": "message_new",
  "chat_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

> On receiving this event, call `GET /api/v1/chats/{chat_id}/messages` to fetch the latest messages.

**`message.read` Payload:**

```json
{
  "type": "message_read",
  "chat_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "last_read_message_id": "f1e2d3c4-b5a6-7890-abcd-ef1234567890"
}
```

> Use `last_read_message_id` to update read receipt indicators in the UI without a full re-fetch.

---

### Fallback Behavior

Pusher Channels delivery is **best-effort**:

- If Pusher is unavailable or the WebSocket connection drops, messages are **still saved to the database**. No data is lost.
- Clients should implement a **polling fallback** for resilience:

```
GET /api/v1/chats/{chat_id}/messages
```

Recommended fallback strategy:

```
1. Connect to Pusher WebSocket on app open.
2. On connection error or disconnect → start polling every 5–10 seconds.
3. On reconnect → stop polling, re-subscribe to channels.
4. On app resume from background → force a REST fetch to catch missed events.
```

If `REALTIME_PROVIDER` is not `pusher` on the server, no events will be published. The REST API remains fully functional.

---

## Pusher Beams — Push Notifications

### Setup & Configuration

Pusher Beams delivers push notifications to devices via platform-native channels:

| Platform | Underlying Service |
|---|---|
| iOS | APNs (Apple Push Notification service) |
| Android | FCM (Firebase Cloud Messaging) |
| Web | Web Push (VAPID) |

The backend publishes notifications via:

```
POST https://rest.pusher.com/publish-api/v1/instances/{instanceId}/publishes/interests/{interest}
Authorization: Bearer {secret_key}
```

> This is handled entirely server-side. Clients only need to register their device token.

---

### Interest Naming

Each user is subscribed to a personal **interest** that matches their user UUID:

```
user-{user_uuid}
```

**Example:**

```
user-01984af1-3b2c-7d8e-9f0a-1b2c3d4e5f6a
```

The client SDK must subscribe to this interest after authenticating. The interest name is deterministic — derive it from the authenticated user's UUID.

**Example (JavaScript/Web):**

```javascript
import * as PusherPushNotifications from '@pusher/push-notifications-web';

const beamsClient = new PusherPushNotifications.Client({
  instanceId: PUSHER_BEAMS_INSTANCE_ID,
});

await beamsClient.start();
await beamsClient.addDeviceInterest(`user-${currentUser.id}`);
```

**Example (Flutter — Android/iOS):**

```dart
await PushNotifications.start(instanceId: pusherBeamsInstanceId);
await PushNotifications.addDeviceInterest('user-${currentUser.id}');
```

---

### Device Registration Flow

Before push notifications can be delivered, the device token must be registered with the Uni-Stash backend. This stores the token in the `device_tokens` table and associates it with the authenticated user.

**Endpoint:**

```
POST /api/v1/notifications/register-device
Authorization: Bearer {jwt_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "token": "device_push_token_from_apns_or_fcm",
  "platform": "ios"
}
```

| Field | Type | Required | Values |
|---|---|---|---|
| `token` | string | ✅ | Device push token from APNs / FCM / Web Push |
| `platform` | string | ✅ | `ios`, `android`, `web` |

**Registration Flow:**

```
App Start / Login
      │
      ▼
Request push permission from OS
      │
      ▼
Receive device token (APNs / FCM)
      │
      ▼
POST /api/v1/notifications/register-device
  { token, platform }
      │
      ▼
Subscribe to Pusher Beams interest:
  user-{user_uuid}
      │
      ▼
Ready to receive push notifications
```

> **Re-register on token refresh.** APNs and FCM may issue new tokens. Listen for token refresh callbacks and re-call the registration endpoint with the new token.

---

### Push Payload Examples

The backend sends platform-specific payloads. The `data` field (FCM/Android) carries structured key-value pairs for in-app routing.

**iOS (APNs via Pusher Beams):**

```json
{
  "aps": {
    "alert": {
      "title": "New message from Alex",
      "body": "Hey, is the textbook still available?"
    },
    "sound": "default"
  }
}
```

**Android (FCM via Pusher Beams):**

```json
{
  "notification": {
    "title": "New message from Alex",
    "body": "Hey, is the textbook still available?"
  },
  "data": {
    "type": "message_new",
    "chat_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  }
}
```

> The `data` object contains key-value pairs passed by the feature code. Use these for deep-linking or in-app navigation when the notification is tapped.

**Web Push:**

```json
{
  "notification": {
    "title": "New message from Alex",
    "body": "Hey, is the textbook still available?"
  }
}
```

**Handling Notification Taps (Android example):**

```kotlin
// In your FirebaseMessagingService or notification handler
val chatId = remoteMessage.data["chat_id"]
val type = remoteMessage.data["type"]

if (type == "message_new" && chatId != null) {
    // Navigate to the chat screen
    navigateToChat(chatId)
}
```

---

## Integration Checklist

Use this checklist when integrating realtime features into a new client.

### Pusher Channels (Chat)

- [ ] Obtain `PUSHER_APP_KEY` and `PUSHER_CLUSTER` from the backend team / environment config
- [ ] Initialize the Pusher client SDK with the auth endpoint: `POST /api/v1/realtime/auth`
- [ ] Pass the user's JWT token in the `Authorization` header of auth requests
- [ ] Subscribe to `private-chat-{chat_uuid}` when opening a chat screen
- [ ] Subscribe to `private-user-{user_uuid}` once per session (in-app notifications + live thread list for chats you are not viewing)
- [ ] Bind handlers for `message.new` and `message.read` events
- [ ] On `message.new` → call `GET /api/v1/chats/{id}/messages` to fetch new messages
- [ ] On `message.read` → update read receipt state locally using `last_read_message_id`
- [ ] Implement polling fallback (`GET /api/v1/chats/{id}/messages`) on WebSocket disconnect
- [ ] Unsubscribe from channels when leaving the chat screen to avoid memory leaks
- [ ] Force a REST fetch on app resume from background to catch missed events

### Pusher Beams (Push Notifications)

- [ ] Obtain `PUSHER_BEAMS_INSTANCE_ID` from the backend team / environment config
- [ ] Request push notification permission from the OS on first launch (after login)
- [ ] Retrieve the device token from APNs (iOS) or FCM (Android)
- [ ] Call `POST /api/v1/notifications/register-device` with `{token, platform}` after login
- [ ] Re-register the device token whenever APNs / FCM issues a refreshed token
- [ ] Subscribe to the Pusher Beams interest `user-{user_uuid}` after authentication
- [ ] Unsubscribe from the interest and deregister the token on logout
- [ ] Handle notification taps: read the `data` field (Android/FCM) for deep-link routing
- [ ] Test on a physical device — push notifications do not work on simulators (iOS)

---

## Environment Variables Reference

These variables must be configured on the backend server. Clients use the public keys only.

| Variable | Required | Description | Example |
|---|---|---|---|
| `REALTIME_PROVIDER` | No | Realtime backend provider. Set to `pusher` to enable Pusher Channels. If unset or any other value, a NullPublisher is used (no-op). | `pusher` |
| `PUSHER_APP_ID` | Yes (if Pusher) | Pusher Channels application ID | `1234567` |
| `PUSHER_APP_KEY` | Yes (if Pusher) | Pusher Channels public app key — **shared with clients** | `abcdef1234567890` |
| `PUSHER_APP_SECRET` | Yes (if Pusher) | Pusher Channels secret — **server-side only, never expose to clients** | `secret123` |
| `PUSHER_CLUSTER` | Yes (if Pusher) | Pusher Channels cluster region — **shared with clients** | `eu`, `us2`, `ap2` |
| `PUSHER_BEAMS_INSTANCE_ID` | Yes (if Beams) | Pusher Beams instance ID — **shared with clients** | `a1b2c3d4-e5f6-...` |
| `PUSHER_BEAMS_SECRET_KEY` | Yes (if Beams) | Pusher Beams secret key — **server-side only, never expose to clients** | `BEAMS-SECRET-...` |

> **Security note:** Never embed `PUSHER_APP_SECRET` or `PUSHER_BEAMS_SECRET_KEY` in client-side code or mobile app bundles. Only the public `APP_KEY`, `CLUSTER`, and `BEAMS_INSTANCE_ID` are safe to ship to clients.

---

*This document is part of the Uni-Stash API Postman workspace. For REST API reference, see the Uni-Stash API collection.*
