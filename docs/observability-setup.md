# UniStash API — Metrics & Logging Setup (Free Tier)

Cheapest viable stack: **Prometheus metrics via Grafana Cloud Free Tier** (10k metrics series, 50 GB logs, 14-day retention — no credit card) + the API's existing `tracing` JSON logs. Zero self-hosted infrastructure.

**Chosen stack**

| Concern                    | Tool                                                              | Cost                |
| -------------------------- | ----------------------------------------------------------------- | ------------------- |
| Metrics scrape/storage     | Grafana Cloud Prometheus (pulls your public `/metrics`)           | Free (10k series)   |
| Dashboards + alerts        | Grafana Cloud                                                     | Free                |
| Logs                       | Render **Log Streams** → Grafana Cloud Loki                       | Free                |
| Runtime metrics exposition | `metrics` + `metrics-exporter-prometheus` crates (`GET /metrics`) | Already implemented |

> Note: Render's **Metrics Stream** (push OTLP to a provider) is Pro-only —
> we don't use it. Grafana Cloud pulls metrics instead, and logs go through
> Log Streams which is free.

---

## 1. What was implemented in the API

- **`GET /metrics`** endpoint (`src/lib.rs`) — Prometheus text exposition format.
  - `METRICS_ENABLED=true/false` (default `true`); `false` → 404.
  - `METRICS_TOKEN` — when set, requires `Authorization: Bearer <token>`.
- **Recorder** (`src/core/metrics.rs`) installed at boot in `main.rs`:
  - `http_requests_total{method, route, status}` — counter
  - `http_request_duration_seconds{method, route}` — histogram (5ms–30s buckets)
  - `http_requests_in_flight` — gauge
  - `db_pool_size` / `db_pool_idle` / `db_pool_in_use` — gauges, sampled every 15s
  - Route labels use matched patterns (`/api/v1/listings/{id}`), never raw UUID paths — cardinality stays bounded.
- **Logging** (`src/core/logging.rs`) — already existed: `tracing` + `tracing-actix-web`, one canonical line per request with method/path/status/latency/request_id. JSON in `ENV=prod`, compact lines otherwise. `RUST_LOG` filters.

### Env vars to add (all optional)

```bash
# apps/api/.env (already in .env.example)
METRICS_ENABLED=true          # default true
METRICS_TOKEN=openssl-rand-hex-32-output
```

No other new env vars. `RUST_LOG=info` (existing) controls log verbosity.

---

## 2. Option A — Grafana Cloud (recommended, fully free)

### One-time setup (~30 min)

1. **Create a free account** → https://grafana.com/auth/sign-up (choose "Grafana Cloud Free").
2. In the portal, note your **instance** (e.g. `https://yourorg.grafana.net`), then **Connections → Prometheus → "scrape metrics"**: you'll get a **remote-write endpoint** and an **API token** (looks like `glc_...`).
3. The push endpoint format is `https://prometheus-prod-XX.grafana.net/api/prom/push`.

### Scrape path

Render's own "Metrics Stream" (push OTLP) is **Pro-only**, so on the free plan
the direction is reversed: **Grafana Cloud scrapes your app's public
`/metrics` URL**. No extra infra on Render at all.

- **Prod (Render)**: in Grafana Cloud go to **Integrations → HTTP metrics
  endpoint** ("scrape a public endpoint"), enter
  `https://your-api.onrender.com/metrics` and add the header
  `Authorization: Bearer <METRICS_TOKEN>`. Grafana scrapes every 60s for
  free.
  - ⚠️ Render **free instances sleep** after ~15 min of no traffic, so
    metrics will have gaps while asleep, and each cold start resets process
    counters/gauges (rates still work; absolute counters reset). Set
    `MIN_INSTANCES=1` or accept the gaps.
- **Local dev**: run one container that scrapes and remote-writes:

```yaml
# docker-compose.observability.yml (run next to the API)
services:
  alloy: # Grafana's collector (successor of promtail/agent)
    image: grafana/alloy:latest
    ports: ["12345:12345"]
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
    environment:
      GCLOUD_TOKEN: glc_your_token_here
```

`config.alloy` (scrape → remote write):

```alloy
prometheus.scrape "unistash" {
  targets = [{ "host" = "host.docker.internal:8080", "__metrics_path__" = "/metrics" }]
  scrape_interval = "15s"
  forward_to = [prometheus.remote_write.grafana.receiver]
}

prometheus.remote_write "grafana" {
  endpoint {
    url = "https://prometheus-prod-XX.grafana.net/api/prom/push"
    basic_auth {
      username = "your-instance-id"
      password = sys.env("GCLOUD_TOKEN")
    }
  }
}
```

### Dashboards worth building (import → add panels)

| Panel            | Query                                                                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Requests/sec     | `sum(rate(http_requests_total[5m]))`                                                                                                   |
| Error rate (5xx) | `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))`                                               |
| p95 latency      | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))`                                                |
| Slowest routes   | `topk(5, sum(rate(http_request_duration_seconds_sum[5m])) by (route) / sum(rate(http_request_duration_seconds_count[5m])) by (route))` |
| Pool saturation  | `db_pool_in_use / db_pool_size`                                                                                                        |
| In-flight        | `http_requests_in_flight`                                                                                                              |

### Alerts (free tier includes them)

- 5xx error rate > 2% for 5 min
- p95 latency > 2s for 10 min
- `db_pool_in_use / db_pool_size` > 0.9 for 10 min (pool too small / slow queries)
- Endpoint down (no successful scrape for 3 min)

### Logs (free on Render)

Render's **Log Streams** (Observability → Log Streams → "Set default") is
available on the free plan, unlike Metrics Stream:

- Set a default destination → choose **Grafana Cloud Loki** (get the URL + a
  logs API token from Grafana Cloud: Connections → Logs).
- No code changes — the API already logs one JSON line per request with
  `request_id`, `http.target`, `status`, `latency_ms`, so log lines correlate
  with metric spikes.

If you skip this, Render's built-in log viewer in the service page is already
usable for free.

---

## 3. Option B — Fully self-hosted (free forever, ~10 min)

For local-only dashboards without a Grafana Cloud account:

```yaml
# docker-compose.observability.yml
services:
  prometheus:
    image: prom/prometheus:latest
    ports: ["9090:9090"]
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
  grafana:
    image: grafana/grafana:latest
    ports: ["3001:3000"]
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
```

`prometheus.yml`:

```yaml
scrape_configs:
  - job_name: uni-stash-api
    scrape_interval: 15s
    metrics_path: /metrics
    # When METRICS_TOKEN is set, add:
    # authorization:
    #   credentials: <token>
    static_configs:
      - targets: ["host.docker.internal:8080"]
```

`docker compose -f docker-compose.observability.yml up -d`, then Grafana at `http://localhost:3001` (admin/admin) → add Prometheus data source `http://prometheus:9090` → same dashboard panels as above.

---

## 4. Security checklist

- [ ] Set `METRICS_TOKEN` in prod (generate: `openssl rand -hex 32`).
- [ ] Serve `/metrics` publicly only when the token is set — otherwise scrape from inside the private network.
- [ ] `METRICS_ENABLED=false` for any environment that must not expose metrics.
- [ ] Route labels never contain user IDs or raw paths — no PII leaks into metrics.

## 5. What's intentionally NOT included (and why)

- **OpenTelemetry tracing spans** — heavier deps, needs a trace backend; JSON request logs + RED metrics cover the free-tier observability need. Add `tracing-opentelemetry` later if distributed tracing becomes necessary.
- **Self-hosted Loki** — Render's log drain to Grafana Cloud covers logs for free; a local Loki container is optional.
