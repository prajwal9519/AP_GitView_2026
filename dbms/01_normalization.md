# GitView — Database Normalization (CP1)

> **Status:** Initial conceptual database design for the GitView course project.  
> **Scope:** This document is based on the proposed project idea. The schema is provisional and will be refined as the AP application is implemented.

## 1. Project context

GitView is a web application where a user submits a GitHub repository URL, explores its files and source code, and requests a live preview of a supported project running in an isolated environment.

The database may need to store:

- user account details used for authentication;
- GitHub repositories added to GitView;
- which users have added which repositories;
- preview sessions and their status;
- technologies detected in each repository;
- dependencies found in repository manifest files; and
- repository file metadata used by the explorer.

The AI repository assistant is a proposed future feature and is not included in this first database design.

## 2. Assumptions and business rules

1. A user can add multiple GitHub repositories.
2. A GitHub repository can be added by multiple GitView users.
3. A repository can have multiple preview sessions over time.
4. Each preview session belongs to one user and one repository that the user has added.
5. A repository can use multiple technologies, and a technology can appear in multiple repositories.
6. A repository can declare multiple software dependencies. The same package can be used by multiple repositories.
7. A repository file path is unique within that repository.
8. User passwords are stored as password hashes, never as plain text.

These are design assumptions, not claims about implemented functionality.

## 3. Unnormalized form (UNF)

A first rough design might try to keep all information about a repository preview in one record:

```text
PreviewRecord(
    session_id,
    user_id, user_name, user_email,
    repository_id, github_url, repository_name,
    session_status, started_at, preview_url,
    technologies [
        { technology_name, category_name, detected_version }, ...
    ],
    dependencies [
        { manifest_path, ecosystem, package_name, version_spec, dependency_type }, ...
    ],
    files [
        { file_path, file_type, file_size_bytes }, ...
    ]
)
```

This is **not normalized** because `technologies`, `dependencies`, and `files` are repeating groups / multi-valued attributes. A single record contains collections rather than one atomic value for each field. Repository and user information would also be repeated across preview records.

## 4. First Normal Form (1NF)

A relation is in **1NF** when every field contains a single atomic value and there are no repeating groups or nested lists.

To reach 1NF, separate the repeating collections into their own relations. A preliminary 1NF representation is:

| Relation | Candidate primary key | Example attributes |
|---|---|---|
| `PreviewSessions_1NF` | `session_id` | `user_id`, `user_name`, `user_email`, `repository_id`, `github_url`, `repository_name`, `session_status`, `started_at`, `preview_url` |
| `RepositoryTechnologies_1NF` | (`repository_id`, `technology_name`) | `github_url`, `repository_name`, `category_name`, `detected_version` |
| `RepositoryDependencies_1NF` | (`repository_id`, `manifest_path`, `ecosystem`, `package_name`) | `github_url`, `repository_name`, `version_spec`, `dependency_type` |
| `RepositoryFiles_1NF` | (`repository_id`, `file_path`) | `file_type`, `file_size_bytes` |

Each row now represents one preview session, one repository-technology association, one dependency declaration, or one repository file. All attributes are atomic.

However, repository details are repeated in the technology and dependency relations. The composite-key relations can also contain partial dependencies, so the design needs further normalization.

## 5. Second Normal Form (2NF)

A relation is in **2NF** when it is in 1NF and every non-key attribute depends on the whole candidate key, not just part of a composite candidate key. This mainly matters for relations with composite keys.

For example, in `RepositoryTechnologies_1NF`, the key is (`repository_id`, `technology_name`):

- `github_url` and `repository_name` depend only on `repository_id`;
- `category_name` depends on `technology_name`;
- `detected_version` depends on the combination of `repository_id` and `technology_name`.

The first two are partial dependencies. Move repository and technology details into their own relations, leaving the association-specific attribute in the junction relation.

A 2NF decomposition is:

| Relation | Primary key | Attributes |
|---|---|---|
| `Users_2NF` | `user_id` | `user_name`, `email`, `password_hash`, `created_at` |
| `Repositories_2NF` | `repository_id` | `github_url`, `repository_name`, `github_owner`, `default_branch` |
| `Technologies_2NF` | `technology_name` | `category_name`, `category_description` |
| `RepositoryTechnologies_2NF` | (`repository_id`, `technology_name`) | `detected_version` |
| `Packages_2NF` | `package_id` | `ecosystem`, `package_name`, `package_description` |
| `RepositoryDependencies_2NF` | (`repository_id`, `manifest_path`, `package_id`) | `version_spec`, `dependency_type` |
| `PreviewSessions_2NF` | `session_id` | `user_id`, `user_name`, `user_email`, `repository_id`, `github_url`, `session_status`, `started_at`, `expires_at`, `preview_url` |
| `RepositoryFiles_2NF` | (`repository_id`, `file_path`) | `file_type`, `file_size_bytes`, `last_scanned_at` |

The 2NF relations remove the partial dependencies from the composite-key technology and dependency relations. `PreviewSessions_2NF` has a single-column key, so it cannot have a partial dependency; it can still have transitive dependencies, which are addressed in 3NF.

## 6. Third Normal Form (3NF)

A relation is in **3NF** when it is in 2NF and non-key attributes do not depend transitively on a candidate key through another non-key attribute.

Examples of transitive dependencies in the 2NF representation:

- `session_id → user_id → user_name, user_email`
- `session_id → repository_id → github_url`
- `technology_name → category_name → category_description`

For example, a user's email belongs to the user record, not to every preview session they create. Similarly, category descriptions belong to a technology category, rather than being repeated for every technology in that category.

The following is the proposed **3NF schema**:

| Relation | Primary key | Other attributes / foreign keys |
|---|---|---|
| `Users` | `user_id` | `user_name`, `email` (unique), `password_hash`, `created_at` |
| `Repositories` | `repository_id` | `github_url` (unique canonical URL), `github_owner`, `repository_name`, `default_branch`, `created_at` |
| `UserRepositories` | (`user_id`, `repository_id`) | `added_at`; `user_id` references `Users`, `repository_id` references `Repositories` |
| `PreviewSessions` | `session_id` | `user_id`, `repository_id`, `session_status`, `started_at`, `expires_at`, `preview_url`; user/repository pair should refer to `UserRepositories` |
| `TechnologyCategories` | `category_id` | `category_name` (unique), `category_description` |
| `Technologies` | `technology_id` | `technology_name` (unique), `category_id` references `TechnologyCategories` |
| `RepositoryTechnologies` | (`repository_id`, `technology_id`) | `detected_version`; references `Repositories` and `Technologies` |
| `Packages` | `package_id` | `ecosystem`, `package_name`, `package_description`; (`ecosystem`, `package_name`) is unique |
| `RepositoryDependencies` | (`repository_id`, `manifest_path`, `package_id`) | `version_spec`, `dependency_type`; references `Repositories` and `Packages` |
| `RepositoryFiles` | (`repository_id`, `file_path`) | `file_type`, `file_size_bytes`, `last_scanned_at`; `repository_id` references `Repositories` |

### Why this is 3NF

- User details are stored once in `Users`; preview sessions store only `user_id`.
- Repository details are stored once in `Repositories`; preview sessions and other relations refer to `repository_id`.
- `UserRepositories` represents the many-to-many relationship between users and repositories.
- Technology category information is separated into `TechnologyCategories`; `Technologies` stores only the category reference.
- `Packages` stores package-level information once. `RepositoryDependencies` stores facts specific to a package used by a repository, such as the version requirement and whether it is a production or development dependency.
- Repository file metadata is stored separately, with the repository and file path identifying each file.

## 7. Boyce–Codd Normal Form (BCNF) — optional check

BCNF requires that, for every non-trivial functional dependency `X → Y`, `X` must be a superkey. Under the uniqueness rules and business assumptions listed in this document, the proposed 3NF relations are also intended to satisfy BCNF:

- `Users`: `user_id` is the primary key and `email` is unique.
- `Repositories`: `repository_id` is the primary key and `github_url` is unique.
- `TechnologyCategories`: `category_id` is the primary key and `category_name` is unique.
- `Technologies`: `technology_id` is the primary key and `technology_name` is unique.
- `Packages`: `package_id` is the primary key and (`ecosystem`, `package_name`) is unique.
- `PreviewSessions`: `session_id` is the primary key.
- The junction and file relations use their stated composite primary keys; their remaining attributes depend on the complete key.

This BCNF assessment depends on the stated candidate keys and uniqueness constraints. It should be revisited if the implementation introduces additional rules, such as multiple detected versions of the same technology in one repository or multiple dependency declarations with the same package in one manifest.

## 8. Summary

The design begins with one unnormalized preview record containing nested lists. It is converted to 1NF by separating repeating groups, to 2NF by removing partial dependencies from composite-key relations, and to 3NF by moving transitive user, repository, and technology-category details into their own relations. The resulting conceptual schema uses primary keys, foreign keys, unique constraints, and junction tables to represent the relationships in GitView.

**Note:** This is a CP1 database-design draft, not a claim that these tables or features have already been implemented. The final schema may change when the AP backend and actual data requirements are developed.
