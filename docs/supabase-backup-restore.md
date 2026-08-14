# Supabase logical backup and restore test

This procedure restores a timestamped logical `.sql` dump into a **new, disposable Supabase project**. It never operates on the source project unless its connection variables are deliberately supplied to the backup command.

## What this backup contains

`pg_dump` captures database schemas, tables, functions, triggers, sequences, and row data, including database metadata used by Supabase Auth and Storage. It does **not** capture Supabase Storage object bytes, Edge Function source/secrets, project API settings, custom domains, or database-wide role passwords. Back those up separately.

## Prerequisites

1. Install PostgreSQL client tools matching the source major version (PostgreSQL 17): `pg_dump`, `pg_restore`, and `psql`.
2. Create a fresh Supabase project for the restore test. Use the same PostgreSQL major version and preferably the same region.
3. In the new project, open **Connect**, select the **Session pooler**, and copy its connection parameters. Use the session pooler for `pg_dump`/`psql`; transaction mode is not suitable for these operations.
4. Stop application traffic and background jobs against the disposable target. Do not point production clients at it.

## Create a backup

Set either one connection string:

```bash
export DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/postgres?sslmode=require'
```

or standard libpq variables (credentials remain in the environment):

```bash
export PGHOST='your-session-pooler-host'
export PGPORT='5432'
export PGDATABASE='postgres'
export PGUSER='your-pooler-user'
export PGPASSWORD='your-database-password'
export PGSSLMODE='require'
```

Run:

```bash
node scripts/backup-supabase.mjs
```

The result is `backups/supabase-YYYY-MM-DDTHH-MM-SSZ.sql`. A successful dump exits with status 0. For SharePoint upload, set `BACKUP_UPLOADER=scripts/upload-backup-sharepoint.mjs` together with the existing `MICROSOFT_TENANT_ID`, `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`, `MICROSOFT_DRIVE_ID`, and `MICROSOFT_ROOT_FOLDER` values. Dumps are stored under `<MICROSOFT_ROOT_FOLDER>/database-backups/` using the timestamped filename.

## Restore into the fresh project

1. Download one off-site dump and verify that its file size is non-zero.
2. Set **target** connection variables. Double-check that `PGHOST`/`DATABASE_URL` belongs to the disposable project, not production.
3. Restore with errors treated as fatal:

```bash
psql --set=ON_ERROR_STOP=1 --single-transaction --file backups/supabase-YYYY-MM-DDTHH-MM-SSZ.sql "$TARGET_DATABASE_URL"
```

If using libpq variables instead, set `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`, and `PGSSLMODE=require`, then omit `"$TARGET_DATABASE_URL"`.

The dump uses `--clean --if-exists`, so restore it only into a fresh/disposable target. Some Supabase-managed objects may already exist; `--if-exists` makes their cleanup repeatable, while `ON_ERROR_STOP` and `--single-transaction` prevent accepting a partial restore.

## Validate the restored project

1. Compare user-table counts on source and target (read-only on both):

   ```sql
   select schemaname, relname, n_live_tup
   from pg_stat_user_tables
   order by schemaname, relname;
   ```

2. Confirm representative critical records and sequence values.
3. Test a new disposable Auth user and the main application flows. Existing sessions/API keys belong to the old project and should not be expected to work.
4. Re-deploy Edge Functions, secrets, Auth/provider settings, webhooks, and custom database role passwords from their separate configuration backups.
5. Restore Storage object bytes from their separate off-site copy. Database rows in `storage` are metadata only.
6. Run Supabase Security and Performance Advisors on the fresh project and resolve any restore-specific warnings.
7. Record the restore duration and test date, then delete or isolate the disposable project according to your retention policy.

## Failure handling

- Do not retry into a partially restored target. Because the command is transactional, a SQL error should roll back the restore; for a clean rehearsal, create another fresh project before retrying.
- A client-version error means the local PostgreSQL tools are older than the server. Install PostgreSQL 17 client tools and repeat the dump.
- Connection failures through a pooler usually indicate the wrong pooler mode, username format, password, port, or missing `sslmode=require`.
