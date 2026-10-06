# rest-api

Run 2026-10-06T20:56:56.924Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| `rest-api-calls.png` | admin | `/my/page` | 15 API calls as manager, reporter and outsider: results, permissions (private subtask hidden, private project 403) and refusals (invalid date 422, depth 99 and "1 OR 1=1" match nothing). |
