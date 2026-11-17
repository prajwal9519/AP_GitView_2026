-- GitView — PostgreSQL Database Schema (CP2)
-- Basis: dbms/01_normalization.md and dbms/02_er_diagram.md
-- Status: Proposed DDL for the planned GitView data model.
-- This script creates the tables; it does not insert application data.
--
-- IMPORTANT NAMING NOTE:
-- CP1 names the relations using PascalCase (for example, Users and PreviewSessions).
-- PostgreSQL folds unquoted identifiers to lowercase, so the table names below
-- are quoted to preserve the exact names used in the CP1 document and ER diagram.

BEGIN;

-- 1. Users: account details for local email/password authentication.
CREATE TABLE "Users" (
    user_id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_name VARCHAR(80) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT chk_users_email_not_blank CHECK (BTRIM(email) <> ''),
    CONSTRAINT chk_users_name_not_blank CHECK (BTRIM(user_name) <> '')
);

-- 2. Repositories: unique GitHub repositories known to GitView.
CREATE TABLE "Repositories" (
    repository_id BIGINT GENERATED ALWAYS AS IDENTITY,
    github_url TEXT NOT NULL,
    github_owner VARCHAR(100) NOT NULL,
    repository_name VARCHAR(100) NOT NULL,
    default_branch VARCHAR(255) NOT NULL DEFAULT 'main',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_repositories PRIMARY KEY (repository_id),
    CONSTRAINT uq_repositories_github_url UNIQUE (github_url),
    CONSTRAINT chk_repositories_github_url_not_blank CHECK (BTRIM(github_url) <> ''),
    CONSTRAINT chk_repositories_owner_not_blank CHECK (BTRIM(github_owner) <> ''),
    CONSTRAINT chk_repositories_name_not_blank CHECK (BTRIM(repository_name) <> '')
);

-- 3. TechnologyCategories: classification shared by technologies.
CREATE TABLE "TechnologyCategories" (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY,
    category_name VARCHAR(100) NOT NULL,
    category_description TEXT,

    CONSTRAINT pk_technology_categories PRIMARY KEY (category_id),
    CONSTRAINT uq_technology_categories_name UNIQUE (category_name),
    CONSTRAINT chk_technology_categories_name_not_blank CHECK (BTRIM(category_name) <> '')
);

-- 4. Technologies: frameworks, languages, tools, and other detected technologies.
CREATE TABLE "Technologies" (
    technology_id BIGINT GENERATED ALWAYS AS IDENTITY,
    technology_name VARCHAR(120) NOT NULL,
    category_id BIGINT NOT NULL,

    CONSTRAINT pk_technologies PRIMARY KEY (technology_id),
    CONSTRAINT uq_technologies_name UNIQUE (technology_name),
    CONSTRAINT chk_technologies_name_not_blank CHECK (BTRIM(technology_name) <> ''),
    CONSTRAINT fk_technologies_category
        FOREIGN KEY (category_id)
        REFERENCES "TechnologyCategories" (category_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

-- 5. Packages: package catalogue, unique within a package ecosystem.
CREATE TABLE "Packages" (
    package_id BIGINT GENERATED ALWAYS AS IDENTITY,
    ecosystem VARCHAR(80) NOT NULL,
    package_name VARCHAR(255) NOT NULL,
    package_description TEXT,

    CONSTRAINT pk_packages PRIMARY KEY (package_id),
    CONSTRAINT uq_packages_ecosystem_name UNIQUE (ecosystem, package_name),
    CONSTRAINT chk_packages_ecosystem_not_blank CHECK (BTRIM(ecosystem) <> ''),
    CONSTRAINT chk_packages_name_not_blank CHECK (BTRIM(package_name) <> '')
);

-- 6. UserRepositories: junction table for the Users <-> Repositories M:N relationship.
CREATE TABLE "UserRepositories" (
    user_id BIGINT NOT NULL,
    repository_id BIGINT NOT NULL,
    added_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_repositories PRIMARY KEY (user_id, repository_id),
    CONSTRAINT fk_user_repositories_user
        FOREIGN KEY (user_id)
        REFERENCES "Users" (user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT fk_user_repositories_repository
        FOREIGN KEY (repository_id)
        REFERENCES "Repositories" (repository_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

-- 7. PreviewSessions: each session belongs to a user/repository association.
CREATE TABLE "PreviewSessions" (
    session_id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id BIGINT NOT NULL,
    repository_id BIGINT NOT NULL,
    session_status VARCHAR(20) NOT NULL DEFAULT 'queued',
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ,
    preview_url TEXT,

    CONSTRAINT pk_preview_sessions PRIMARY KEY (session_id),
    CONSTRAINT fk_preview_sessions_user_repository
        FOREIGN KEY (user_id, repository_id)
        REFERENCES "UserRepositories" (user_id, repository_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT chk_preview_sessions_status
        CHECK (session_status IN ('queued', 'starting', 'running', 'failed', 'stopped', 'expired')),
    CONSTRAINT chk_preview_sessions_expiry
        CHECK (expires_at IS NULL OR expires_at > started_at)
);

-- 8. RepositoryTechnologies: junction table for Repositories <-> Technologies M:N.
CREATE TABLE "RepositoryTechnologies" (
    repository_id BIGINT NOT NULL,
    technology_id BIGINT NOT NULL,
    detected_version VARCHAR(100),

    CONSTRAINT pk_repository_technologies PRIMARY KEY (repository_id, technology_id),
    CONSTRAINT fk_repository_technologies_repository
        FOREIGN KEY (repository_id)
        REFERENCES "Repositories" (repository_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT fk_repository_technologies_technology
        FOREIGN KEY (technology_id)
        REFERENCES "Technologies" (technology_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

-- 9. RepositoryDependencies: dependency declarations found in repository manifests.
CREATE TABLE "RepositoryDependencies" (
    repository_id BIGINT NOT NULL,
    manifest_path TEXT NOT NULL,
    package_id BIGINT NOT NULL,
    version_spec VARCHAR(120) NOT NULL,
    dependency_type VARCHAR(20) NOT NULL,

    CONSTRAINT pk_repository_dependencies
        PRIMARY KEY (repository_id, manifest_path, package_id),
    CONSTRAINT fk_repository_dependencies_repository
        FOREIGN KEY (repository_id)
        REFERENCES "Repositories" (repository_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT fk_repository_dependencies_package
        FOREIGN KEY (package_id)
        REFERENCES "Packages" (package_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT chk_repository_dependencies_manifest_not_blank
        CHECK (BTRIM(manifest_path) <> ''),
    CONSTRAINT chk_repository_dependencies_type
        CHECK (dependency_type IN ('production', 'development', 'optional', 'peer'))
);

-- 10. RepositoryFiles: file metadata used by the repository explorer.
CREATE TABLE "RepositoryFiles" (
    repository_id BIGINT NOT NULL,
    file_path TEXT NOT NULL,
    file_type VARCHAR(80) NOT NULL,
    file_size_bytes BIGINT,
    last_scanned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_repository_files PRIMARY KEY (repository_id, file_path),
    CONSTRAINT fk_repository_files_repository
        FOREIGN KEY (repository_id)
        REFERENCES "Repositories" (repository_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    CONSTRAINT chk_repository_files_path_not_blank CHECK (BTRIM(file_path) <> ''),
    CONSTRAINT chk_repository_files_size CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0)
);

-- Supporting indexes for common lookups and foreign-key joins.
CREATE INDEX idx_user_repositories_repository_id
    ON "UserRepositories" (repository_id);

CREATE INDEX idx_preview_sessions_user_started
    ON "PreviewSessions" (user_id, started_at DESC);

CREATE INDEX idx_preview_sessions_repository_id
    ON "PreviewSessions" (repository_id);

CREATE INDEX idx_technologies_category_id
    ON "Technologies" (category_id);

CREATE INDEX idx_repository_technologies_technology_id
    ON "RepositoryTechnologies" (technology_id);

CREATE INDEX idx_repository_dependencies_package_id
    ON "RepositoryDependencies" (package_id);

COMMIT;

-- Implementation notes:
-- 1. This DDL follows the CP1 3NF entities and relationships.
-- 2. The script creates an empty schema. It does not seed sample users,
--    repositories, technologies, packages, or preview sessions.
-- 3. Validate GitHub URLs and normalize email casing in the application layer.
-- 4. password_hash must contain a bcrypt hash generated by the backend,
--    never a plaintext password.
-- 5. OAuth account records and persisted refresh-token records are outside
--    this version of the CP1 model and can be designed as later additions.
-- 6. The preview execution environment is not implemented by this DDL.
