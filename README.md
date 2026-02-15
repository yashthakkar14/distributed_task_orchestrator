# Job Orchestrator

Distributed job orchestration system built with Rails 7, MySQL, Redis, and Sidekiq.

Per-client concurrency limits, priority-based fair scheduling, exponential backoff retries, and dead worker detection via heartbeat monitoring.

## Live Demo

Deployed on Railway (separate web + worker processes):

- **Health**: https://distributed-task-orchestrator-production.up.railway.app/health/detailed
- **Sidekiq UI**: https://distributed-task-orchestrator-production.up.railway.app/sidekiq
- **Postman API**: [Distributed Task Orchestrator Postman API](https://yashthakkar714-5949505.postman.co/workspace/Yash-Thakkar's-Workspace~7d873bfb-f7a7-411b-865c-b584586948c6/collection/52396870-b59ff1e0-1ad4-4bf1-971a-adb9b43de8d8?action=share&creator=52396870)
- **Try it**:
  ```bash
  curl -X POST https://distributed-task-orchestrator-production.up.railway.app/jobs \
    -H "Content-Type: application/json" \
    -d '{"client_id": "client_alpha", "priority": "high", "workload": "fast_task"}'
  ```

## Setup

```bash
bundle install
rails db:create db:migrate db:seed
redis-server &
bundle exec sidekiq
rails server
```

## Tests

```bash
bundle exec rspec
bundle exec rspec --format documentation
```

## API

### POST /jobs

```bash
curl -X POST http://distributed-task-orchestrator-production.up.railway.app/jobs \
  -H "Content-Type: application/json" \
  -d '{"client_id": "client_alpha", "priority": "high", "workload": "fast_task"}'
```

Fields: `client_id` (required), `workload` (required, one of `fast_task`/`slow_task`/`error_task`), `priority` (optional, `low`/`medium`/`high`), `idempotency_key` (optional).

Returns 201 with `{ id, client_id, status, priority, workload, created_at }`. Errors: 404 if client doesn't exist, 422 on validation errors, 429 if queue depth limit exceeded.

### GET /health/detailed

Returns system health: DB/Redis connectivity, queue depths, per-client slot usage. Returns 503 if anything is degraded.

### Sidekiq UI

Available at /sidekiq for monitoring background queues.

## Architecture

See [DESIGN.md](DESIGN.md) for design decisions, failure modes, and scaling analysis.
