# syntax=docker/dockerfile:1.6
#
# Two-stage build. The builder stage compiles native gems (sqlite3),
# the final stage carries only the runtime libs + the prebuilt bundle.
# Result is ~150 MB.

ARG RUBY_VERSION=3.4

# ── Base: shared between builder and final ─────────────────────────────
FROM ruby:${RUBY_VERSION}-slim-bookworm AS base

ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=1 \
    PORT=3000

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libsqlite3-0 ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Builder: compile gems ──────────────────────────────────────────────
FROM base AS builder

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./

# Ensure the lockfile knows about Linux platforms even if it was generated
# on macOS. Then install with the lock unchanged from then on.
RUN bundle lock --add-platform x86_64-linux \
 && bundle lock --add-platform aarch64-linux \
 && bundle install --jobs 4

# ── Final image ────────────────────────────────────────────────────────
FROM base

# Bring in the prebuilt bundle from the builder stage.
COPY --from=builder /usr/local/bundle /usr/local/bundle

# App code.
COPY . .

RUN chmod +x bin/docker-entrypoint

# Mount points for the bind-mounted state.
VOLUME ["/app/db", "/app/slides"]

EXPOSE 3000

ENTRYPOINT ["bin/docker-entrypoint"]
