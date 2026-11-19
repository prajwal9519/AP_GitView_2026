-- GitView — Application SQL Query Catalogue (CP3)
-- Basis: dbms/03_schema.sql (CP2)
-- Status: Proposed application query set aligned to the submitted schema.
--
-- IMPORTANT:
-- The supplied AP_GitView_2026 archive contains the database design files,
-- but not the application source/query layer. Therefore these are parameterized
-- queries the application can use; they are not claimed to be extracted from
-- existing application code.
--
-- Parameter convention:
--   $1, $2, ... are positional parameters supplied by the application.
--   Always use parameterized execution. Never concatenate user input into SQL.
--
-- Every statement is labelled READ or WRITE as required by CP3.
-- Execute multi-step write workflows in a transaction where indicated.

-- ============================================================================
-- 1. USERS / AUTHENTICATION
-- ============================================================================

-- READ: Find a user by normalized email during login.
SELECT user_id, user_name, email, password_hash, created_at
FROM "Users"
WHERE LOWER(email) = LOWER($1);

-- WRITE: Register a user. The application must pass a password hash, not plaintext.
INSERT INTO "Users" (user_name, email, password_hash)
VALUES ($1, LOWER($2), $3)
RETURNING user_id, user_name, email, created_at;

-- READ: Load the public profile for the authenticated user.
SELECT user_id, user_name, email, created_at
FROM "Users"
WHERE user_id = $1;

-- WRITE: Update the authenticated user's profile.
UPDATE "Users"
SET user_name = $2,
    email = LOWER($3)
WHERE user_id = $1
RETURNING user_id, user_name, email, created_at;

-- ============================================================================
-- 2. REPOSITORIES / USER-REPOSITORY ASSOCIATION
-- ============================================================================

-- WRITE: Add a GitHub repository to a user's collection.
-- Run as one statement: create/find the canonical repository, then link the user.
WITH saved_repository AS (
    INSERT INTO "Repositories"
        (github_url, github_owner, repository_name, default_branch)
    VALUES
        ($2, $3, $4, $5)
    ON CONFLICT (github_url)
    DO UPDATE SET github_url = EXCLUDED.github_url
    RETURNING repository_id
)
INSERT INTO "UserRepositories" (user_id, repository_id)
SELECT $1, repository_id
FROM saved_repository
ON CONFLICT (user_id, repository_id) DO NOTHING
RETURNING user_id, repository_id, added_at;

-- READ: List repositories saved by a user.
SELECT
    r.repository_id,
    r.github_url,
    r.github_owner,
    r.repository_name,
    r.default_branch,
    ur.added_at
FROM "UserRepositories" AS ur
JOIN "Repositories" AS r
    ON r.repository_id = ur.repository_id
WHERE ur.user_id = $1
ORDER BY ur.added_at DESC;

-- READ: Get one repository only when it belongs to the requesting user.
SELECT
    r.repository_id,
    r.github_url,
    r.github_owner,
    r.repository_name,
    r.default_branch,
    ur.added_at
FROM "Repositories" AS r
JOIN "UserRepositories" AS ur
    ON ur.repository_id = r.repository_id
WHERE ur.user_id = $1
  AND r.repository_id = $2;

-- READ: Search repositories in the authenticated user's collection.
SELECT
    r.repository_id,
    r.github_owner,
    r.repository_name,
    r.github_url,
    r.default_branch
FROM "UserRepositories" AS ur
JOIN "Repositories" AS r
    ON r.repository_id = ur.repository_id
WHERE ur.user_id = $1
  AND (
      r.repository_name ILIKE '%' || $2 || '%'
      OR r.github_owner ILIKE '%' || $2 || '%'
  )
ORDER BY r.repository_name;

-- WRITE: Remove a repository from a user's collection.
-- Related preview sessions are removed through the schema's cascading FK.
DELETE FROM "UserRepositories"
WHERE user_id = $1
  AND repository_id = $2
RETURNING user_id, repository_id;

-- WRITE: Update repository metadata.
UPDATE "Repositories"
SET github_owner = $2,
    repository_name = $3,
    default_branch = $4,
    github_url = $5
WHERE repository_id = $1
RETURNING repository_id, github_url, github_owner, repository_name, default_branch;

-- ============================================================================
-- 3. PREVIEW SESSIONS
-- ============================================================================

-- WRITE: Create a preview session only if the user has saved the repository.
INSERT INTO "PreviewSessions"
    (user_id, repository_id, session_status, expires_at, preview_url)
SELECT
    ur.user_id,
    ur.repository_id,
    $3,
    $4,
    $5
FROM "UserRepositories" AS ur
WHERE ur.user_id = $1
  AND ur.repository_id = $2
RETURNING session_id, user_id, repository_id, session_status,
          started_at, expires_at, preview_url;

-- READ: List preview-session history for a user, including repository details.
SELECT
    ps.session_id,
    ps.session_status,
    ps.started_at,
    ps.expires_at,
    ps.preview_url,
    r.repository_id,
    r.github_owner,
    r.repository_name,
    r.github_url
FROM "PreviewSessions" AS ps
JOIN "Repositories" AS r
    ON r.repository_id = ps.repository_id
JOIN "UserRepositories" AS ur
    ON ur.user_id = ps.user_id
   AND ur.repository_id = ps.repository_id
WHERE ps.user_id = $1
ORDER BY ps.started_at DESC;

-- READ: Get one preview session with repository details, scoped to its owner.
SELECT
    ps.session_id,
    ps.session_status,
    ps.started_at,
    ps.expires_at,
    ps.preview_url,
    r.repository_id,
    r.github_owner,
    r.repository_name,
    r.github_url
FROM "PreviewSessions" AS ps
JOIN "Repositories" AS r
    ON r.repository_id = ps.repository_id
WHERE ps.session_id = $1
  AND ps.user_id = $2;

-- READ: Get recent preview sessions for one repository belonging to the user.
SELECT
    ps.session_id,
    ps.session_status,
    ps.started_at,
    ps.expires_at,
    ps.preview_url
FROM "PreviewSessions" AS ps
JOIN "UserRepositories" AS ur
    ON ur.user_id = ps.user_id
   AND ur.repository_id = ps.repository_id
WHERE ps.user_id = $1
  AND ps.repository_id = $2
ORDER BY ps.started_at DESC;

-- WRITE: Update a preview session's status and expiry information.
UPDATE "PreviewSessions"
SET session_status = $3,
    expires_at = $4,
    preview_url = $5
WHERE session_id = $1
  AND user_id = $2
RETURNING session_id, session_status, started_at, expires_at, preview_url;

-- WRITE: Mark a preview session as stopped, scoped to its owner.
UPDATE "PreviewSessions"
SET session_status = 'stopped',
    expires_at = NULL,
    preview_url = NULL
WHERE session_id = $1
  AND user_id = $2
  AND session_status IN ('queued', 'starting', 'running')
RETURNING session_id, session_status, started_at;

-- WRITE: Mark sessions whose expiry time has passed as expired.
UPDATE "PreviewSessions"
SET session_status = 'expired',
    preview_url = NULL
WHERE session_status IN ('queued', 'starting', 'running')
  AND expires_at IS NOT NULL
  AND expires_at <= CURRENT_TIMESTAMP
RETURNING session_id, user_id, repository_id, session_status;

-- ============================================================================
-- 4. TECHNOLOGY CATEGORIES / TECHNOLOGIES
-- ============================================================================

-- READ: List the technology catalogue with category names and descriptions.
SELECT
    t.technology_id,
    t.technology_name,
    tc.category_id,
    tc.category_name,
    tc.category_description
FROM "Technologies" AS t
JOIN "TechnologyCategories" AS tc
    ON tc.category_id = t.category_id
ORDER BY tc.category_name, t.technology_name;

-- WRITE: Create a technology category.
INSERT INTO "TechnologyCategories" (category_name, category_description)
VALUES ($1, $2)
RETURNING category_id, category_name, category_description;

-- WRITE: Add a technology to a category.
INSERT INTO "Technologies" (technology_name, category_id)
VALUES ($1, $2)
RETURNING technology_id, technology_name, category_id;

-- WRITE: Associate a detected technology with a repository.
INSERT INTO "RepositoryTechnologies"
    (repository_id, technology_id, detected_version)
VALUES ($1, $2, $3)
ON CONFLICT (repository_id, technology_id)
DO UPDATE SET detected_version = EXCLUDED.detected_version
RETURNING repository_id, technology_id, detected_version;

-- READ: Get technologies detected in a repository, including their categories.
SELECT
    r.repository_id,
    r.repository_name,
    t.technology_id,
    t.technology_name,
    tc.category_name,
    tc.category_description,
    rt.detected_version
FROM "RepositoryTechnologies" AS rt
JOIN "Repositories" AS r
    ON r.repository_id = rt.repository_id
JOIN "Technologies" AS t
    ON t.technology_id = rt.technology_id
JOIN "TechnologyCategories" AS tc
    ON tc.category_id = t.category_id
WHERE rt.repository_id = $1
ORDER BY tc.category_name, t.technology_name;

-- ============================================================================
-- 5. PACKAGES / REPOSITORY DEPENDENCIES
-- ============================================================================

-- READ: Find a package by ecosystem and package name.
SELECT package_id, ecosystem, package_name, package_description
FROM "Packages"
WHERE LOWER(ecosystem) = LOWER($1)
  AND LOWER(package_name) = LOWER($2);

-- WRITE: Add a package to the shared package catalogue.
INSERT INTO "Packages" (ecosystem, package_name, package_description)
VALUES ($1, $2, $3)
ON CONFLICT (ecosystem, package_name)
DO UPDATE SET package_description = COALESCE(
    EXCLUDED.package_description,
    "Packages".package_description
)
RETURNING package_id, ecosystem, package_name, package_description;

-- WRITE: Record a package dependency declared by a repository manifest.
INSERT INTO "RepositoryDependencies"
    (repository_id, manifest_path, package_id, version_spec, dependency_type)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (repository_id, manifest_path, package_id)
DO UPDATE SET
    version_spec = EXCLUDED.version_spec,
    dependency_type = EXCLUDED.dependency_type
RETURNING repository_id, manifest_path, package_id, version_spec, dependency_type;

-- READ: List all dependencies for a repository with package metadata.
SELECT
    rd.repository_id,
    rd.manifest_path,
    p.package_id,
    p.ecosystem,
    p.package_name,
    p.package_description,
    rd.version_spec,
    rd.dependency_type
FROM "RepositoryDependencies" AS rd
JOIN "Packages" AS p
    ON p.package_id = rd.package_id
WHERE rd.repository_id = $1
ORDER BY rd.manifest_path, p.package_name;

-- READ: List production dependencies for a repository.
SELECT
    p.package_name,
    p.ecosystem,
    rd.version_spec,
    rd.manifest_path
FROM "RepositoryDependencies" AS rd
JOIN "Packages" AS p
    ON p.package_id = rd.package_id
WHERE rd.repository_id = $1
  AND rd.dependency_type = 'production'
ORDER BY p.package_name;

-- WRITE: Remove a dependency declaration from a repository manifest.
DELETE FROM "RepositoryDependencies"
WHERE repository_id = $1
  AND manifest_path = $2
  AND package_id = $3
RETURNING repository_id, manifest_path, package_id;

-- ============================================================================
-- 6. REPOSITORY FILES
-- ============================================================================

-- WRITE: Insert or refresh file metadata discovered by the repository explorer.
INSERT INTO "RepositoryFiles"
    (repository_id, file_path, file_type, file_size_bytes, last_scanned_at)
VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
ON CONFLICT (repository_id, file_path)
DO UPDATE SET
    file_type = EXCLUDED.file_type,
    file_size_bytes = EXCLUDED.file_size_bytes,
    last_scanned_at = CURRENT_TIMESTAMP
RETURNING repository_id, file_path, file_type, file_size_bytes, last_scanned_at;

-- READ: List repository files with repository details.
SELECT
    r.repository_id,
    r.repository_name,
    rf.file_path,
    rf.file_type,
    rf.file_size_bytes,
    rf.last_scanned_at
FROM "RepositoryFiles" AS rf
JOIN "Repositories" AS r
    ON r.repository_id = rf.repository_id
WHERE rf.repository_id = $1
ORDER BY rf.file_path;

-- READ: Find one file metadata record only if the user owns the repository.
SELECT
    rf.repository_id,
    r.repository_name,
    rf.file_path,
    rf.file_type,
    rf.file_size_bytes,
    rf.last_scanned_at
FROM "RepositoryFiles" AS rf
JOIN "Repositories" AS r
    ON r.repository_id = rf.repository_id
JOIN "UserRepositories" AS ur
    ON ur.repository_id = r.repository_id
WHERE ur.user_id = $1
  AND rf.repository_id = $2
  AND rf.file_path = $3;

-- WRITE: Delete file metadata for a path removed from the repository.
DELETE FROM "RepositoryFiles"
WHERE repository_id = $1
  AND file_path = $2
RETURNING repository_id, file_path;

-- ============================================================================
-- 7. DASHBOARD / SUMMARY READS (JOIN-BASED)
-- ============================================================================

-- READ: Dashboard repository summary with preview-session count and latest session.
SELECT
    r.repository_id,
    r.github_owner,
    r.repository_name,
    r.github_url,
    COUNT(ps.session_id) AS preview_session_count,
    MAX(ps.started_at) AS latest_preview_started_at
FROM "UserRepositories" AS ur
JOIN "Repositories" AS r
    ON r.repository_id = ur.repository_id
LEFT JOIN "PreviewSessions" AS ps
    ON ps.user_id = ur.user_id
   AND ps.repository_id = ur.repository_id
WHERE ur.user_id = $1
GROUP BY r.repository_id, r.github_owner, r.repository_name,
         r.github_url, ur.added_at
ORDER BY ur.added_at DESC;

-- READ: Count repositories, preview sessions, technologies and dependencies
-- for a user's dashboard. Each count is isolated in its own subquery to avoid
-- multiplying rows through multiple one-to-many joins.
SELECT
    (SELECT COUNT(*)
     FROM "UserRepositories" ur
     WHERE ur.user_id = $1) AS repository_count,
    (SELECT COUNT(*)
     FROM "PreviewSessions" ps
     WHERE ps.user_id = $1) AS preview_session_count,
    (SELECT COUNT(DISTINCT rt.repository_id)
     FROM "RepositoryTechnologies" rt
     JOIN "UserRepositories" ur
       ON ur.repository_id = rt.repository_id
     WHERE ur.user_id = $1) AS repositories_with_detected_technologies,
    (SELECT COUNT(DISTINCT rd.repository_id)
     FROM "RepositoryDependencies" rd
     JOIN "UserRepositories" ur
       ON ur.repository_id = rd.repository_id
     WHERE ur.user_id = $1) AS repositories_with_dependencies;

-- READ: Show all repositories using a particular technology.
SELECT
    r.repository_id,
    r.github_owner,
    r.repository_name,
    r.github_url,
    t.technology_name,
    rt.detected_version
FROM "RepositoryTechnologies" AS rt
JOIN "Repositories" AS r
    ON r.repository_id = rt.repository_id
JOIN "Technologies" AS t
    ON t.technology_id = rt.technology_id
WHERE t.technology_id = $1
ORDER BY r.repository_name;

-- ============================================================================
-- END OF CP3 QUERY CATALOGUE
-- ============================================================================
