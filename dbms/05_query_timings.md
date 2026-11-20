# CP-4 — PostgreSQL Query Timing Results

> Timings are PostgreSQL `EXPLAIN (ANALYZE)` server-side execution times in milliseconds. Each query was executed three times. Every trial ran inside a transaction that was rolled back, so benchmark writes did not persist.

- Generated: 2026-11-20 16:11:15 UTC
- Database: `gitview_cp4_bench` (dedicated CP-4 benchmark database)
- PostgreSQL: `PostgreSQL 18.6 (Postgres.app) on aarch64-apple-darwin23.6.0, compiled by Apple clang version 15.0.0 (clang-1500.3.9.4), 64-bit`
- Source: [`04_queries.sql`](04_queries.sql)
- Runs per query: 3
- Plan files: [`plans/`](plans/)

| # | Type | Query | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---:|:---:|---|---:|---:|---:|---:|
| 01 | READ | Find a user by normalized email during login. | 0.008 | 0.004 | 0.003 | 0.005 |
| 02 | WRITE | Register a user. The application must pass a password hash, not plaintext. | 0.021 | 0.013 | 0.010 | 0.015 |
| 03 | READ | Load the public profile for the authenticated user. | 0.006 | 0.004 | 0.003 | 0.004 |
| 04 | WRITE | Update the authenticated user's profile. | 0.043 | 0.016 | 0.020 | 0.026 |
| 05 | WRITE | Add a GitHub repository to a user's collection. | 0.071 | 0.038 | 0.035 | 0.048 |
| 06 | READ | List repositories saved by a user. | 0.018 | 0.009 | 0.007 | 0.011 |
| 07 | READ | Get one repository only when it belongs to the requesting user. | 0.008 | 0.005 | 0.032 | 0.015 |
| 08 | READ | Search repositories in the authenticated user's collection. | 0.627 | 0.011 | 0.009 | 0.216 |
| 09 | WRITE | Remove a repository from a user's collection. | 0.068 | 0.020 | 0.018 | 0.035 |
| 10 | WRITE | Update repository metadata. | 0.073 | 0.018 | 0.015 | 0.035 |
| 11 | WRITE | Create a preview session only if the user has saved the repository. | 0.045 | 0.045 | 0.032 | 0.041 |
| 12 | READ | List preview-session history for a user, including repository details. | 0.027 | 0.015 | 0.012 | 0.018 |
| 13 | READ | Get one preview session with repository details, scoped to its owner. | 0.007 | 0.005 | 0.005 | 0.006 |
| 14 | READ | Get recent preview sessions for one repository belonging to the user. | 0.010 | 0.007 | 0.006 | 0.008 |
| 15 | WRITE | Update a preview session's status and expiry information. | 0.038 | 0.032 | 0.021 | 0.030 |
| 16 | WRITE | Mark a preview session as stopped, scoped to its owner. | 0.026 | 0.019 | 0.017 | 0.021 |
| 17 | WRITE | Mark sessions whose expiry time has passed as expired. | 0.022 | 0.018 | 0.027 | 0.022 |
| 18 | READ | List the technology catalogue with category names and descriptions. | 0.016 | 0.007 | 0.005 | 0.009 |
| 19 | WRITE | Create a technology category. | 0.021 | 0.012 | 0.008 | 0.014 |
| 20 | WRITE | Add a technology to a category. | 0.122 | 0.037 | 0.022 | 0.060 |
| 21 | WRITE | Associate a detected technology with a repository. | 0.054 | 0.027 | 0.025 | 0.035 |
| 22 | READ | Get technologies detected in a repository, including their categories. | 0.028 | 0.015 | 0.012 | 0.018 |
| 23 | READ | Find a package by ecosystem and package name. | 0.005 | 0.003 | 0.003 | 0.004 |
| 24 | WRITE | Add a package to the shared package catalogue. | 0.022 | 0.020 | 0.026 | 0.023 |
| 25 | WRITE | Record a package dependency declared by a repository manifest. | 0.057 | 0.036 | 0.093 | 0.062 |
| 26 | READ | List all dependencies for a repository with package metadata. | 0.018 | 0.009 | 0.007 | 0.011 |
| 27 | READ | List production dependencies for a repository. | 0.007 | 0.005 | 0.005 | 0.006 |
| 28 | WRITE | Remove a dependency declaration from a repository manifest. | 0.009 | 0.005 | 0.004 | 0.006 |
| 29 | WRITE | Insert or refresh file metadata discovered by the repository explorer. | 0.039 | 0.022 | 0.019 | 0.027 |
| 30 | READ | List repository files with repository details. | 0.013 | 0.008 | 0.006 | 0.009 |
| 31 | READ | Find one file metadata record only if the user owns the repository. | 0.009 | 0.010 | 0.010 | 0.010 |
| 32 | WRITE | Delete file metadata for a path removed from the repository. | 0.013 | 0.010 | 0.009 | 0.011 |
| 33 | READ | Dashboard repository summary with preview-session count and latest session. | 0.044 | 0.021 | 0.017 | 0.027 |
| 34 | READ | Count repositories, preview sessions, technologies and dependencies | 0.054 | 0.029 | 0.021 | 0.035 |
| 35 | READ | Show all repositories using a particular technology. | 0.017 | 0.009 | 0.008 | 0.011 |

## Methodology and interpretation

1. The runner loaded the 35 labelled statements from `04_queries.sql` and supplied fixed parameters against a deterministic fixture dataset.
2. Each run used `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT JSON)`. The reported value is PostgreSQL's `Execution Time`, not the client/network round-trip time.
3. Each execution was rolled back. This is important because `EXPLAIN ANALYZE` really executes `INSERT`, `UPDATE`, and `DELETE` statements.
4. One JSON execution plan per query (from Run 1) is stored in `plans/`. Each plan includes the actual plan nodes, buffers, planning time, and execution time.
5. These measurements describe the fixture dataset and local PostgreSQL environment. They should not be generalized to production-scale data.
