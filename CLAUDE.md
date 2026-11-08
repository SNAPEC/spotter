# CLAUDE.md

## Project

Spotter is the incident-reporting tool (RETEX) of the SNAPEC, the French union of climbing and canyoning instructors.
Instructors report accidents, incidents and near misses; an open-source LLM proposes an anonymised, coded version; an analyst validates it.
Status: design phase. The proof of concept covers climbing only. Canyoning comes later.

Steering documents (decisions, to-do list, session handover, third-party agreements) live in the private repository `SNAPEC/spotter-pilotage`, cloned next to this one. Product design documents are private too. Ask before assuming a product decision.

## Non-negotiable rules

1. No real data in the repo: no real narrative, claims-file row, name, place, date or screenshot. Tests, seeds and prompt examples are fictional. The repo is public.
2. No secrets in the repo. Keys go through Rails credentials or Kamal secrets.
3. No IP address stored or logged, anywhere. Rate limiting keys on an HMAC of the IP (Solid Cache stores keys in the database).
4. A report never points to its author. The only link is `ReportOwnership`, encrypted, deleted at validation or automatically after a fixed delay. Never add another path (foreign key, log line, job argument, email content).
5. Deletion is automatic and identical for everyone. No manual way to change one report's deletion date.
6. Minimise: dates rounded to the month, places generalised, no victim identity, age ranges.
7. The LLM has no tools and no network access, returns constrained JSON, and never publishes. An analyst always validates.

## Stack

- Rails 8, Hotwire (Turbo, Stimulus), Tailwind, importmap. No JS framework, no Node build.
- PostgreSQL, Solid Queue, Solid Cache, Active Record Encryption, Active Storage on a private Scaleway bucket (EXIF stripped).
- Mistral through Scaleway Generative APIs, via `ruby_llm`, behind a single interface: `extract(text, schema)` returns validated JSON.
- Kamal on a Scaleway VM in France. Sentry (EU, no PII, no IP). One production; pre-production is local.

## Code conventions

- Code, comments and commit messages in English. UI in French through I18n, with English keys.
- Comments only for a non-obvious "why".
- Rails way first; every new gem needs a reason.
- Business logic in rich models. Code that talks to the outside (LLM, membership API) is a plain Ruby class namespaced under its model in `app/models` (`Report::Analyzer`). No `app/services`.
- Controllers only read params, authorise, call one model method, render.
- A GET never writes or triggers a computation.
- A job calls one model method, is idempotent, has explicit `queue_as`, bounded `retry_on`, `discard_on ActiveRecord::RecordNotFound`, and is enqueued after commit.
- `ENV` is read only in `config/`.
- State columns get a database check constraint generated from the Ruby constant.
- Prompts and taxonomy versions are immutable: a change is a new version.
- No legacy code before the first release: delete rather than redirect.

## Tests and linting

- RSpec. A job is tested through its effects. No `allow_any_instance_of`, no `send` to private methods, no `instance_variable_get`.
- `rubocop-rails-omakase` as is. A rule is added only after the same issue comes up twice in review.
- Brakeman and bundler-audit run before every push and in CI.
- No destructive `db:*` task outside `RAILS_ENV=test`. Fix a broken migration, never the database.

## Workflow

- One branch and one pull request per task, merged after review by the other developer. Never push to `main`.
- Critical areas (encryption, ownership deletion, logging, authentication) get an in-depth review.
- Commits: small, one concern, imperative mood ("Add magic link sign-in"). Stage by path, never `git add -A`.
- Agents: `spotter-rails` implements a validated task, `spotter-review` reviews read-only.

## Commands

- `bin/setup`: dependencies, database, fictional seeds on creation, then `bin/dev`.
- `bin/dev`: server and Tailwind watcher (port 3000).
- `bundle exec rspec [paths]`, `bin/rubocop [paths]`, `bin/brakeman --no-pager -q`, `bin/bundler-audit`.
- `bin/rails tailwindcss:build`: compiled CSS (for a screenshot without `bin/dev`).
- `scripts/ci/install-hooks.sh`: once after cloning.
- In development: `/dev/login` (fictional account), `/dev/styleguide` (components).
