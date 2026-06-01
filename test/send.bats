#!/usr/bin/env bats
# Tests for emails send task

bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_agent
  setup_mock_himalaya
}

# ============================================================================
# Argument validation
# ============================================================================

@test "send: fails without arguments" {
  run emails send
  [ "$status" -ne 0 ]
}

@test "send: fails with only recipient" {
  run emails send user@example.com
  [ "$status" -ne 0 ]
}

@test "send: ignores inherited usage_body when body is omitted" {
  usage_body="This inherited body is long enough to pass validation but must not be used" run emails send user@example.com "Subject"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Message body is required"* ]]
  [ ! -s "$MOCK_HIMALAYA_CALLS" ]
}

@test "send: ignores inherited usage_body when only flags are supplied" {
  usage_body="This inherited body is long enough to pass validation but must not be used" run emails send user@example.com "Subject" --html
  [ "$status" -ne 0 ]
  [[ "$output" == *"Message body is required"* ]]
  [ ! -s "$MOCK_HIMALAYA_CALLS" ]
}

@test "send: rejects body supplied positionally and with --body" {
  run emails send user@example.com "Subject" "positional body that is long enough to pass validation" -b "flag body that is long enough to pass validation"
  [ "$status" -ne 0 ]
  [[ "$output" == *"either positionally or with -b/--body"* ]]
  [ ! -s "$MOCK_HIMALAYA_CALLS" ]
}

@test "send: rejects short body without --allow-short" {
  run emails send user@example.com "Test Subject" "hi"
  [ "$status" -ne 0 ]
  [[ "$output" == *"too short"* ]]
}

@test "send: allows short body with --allow-short" {
  run emails send user@example.com "Test Subject" "hi" --allow-short
  [ "$status" -eq 0 ]
  assert_himalaya_called "template send"
}

@test "send: sends with sufficient body length" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send user@example.com "Test Subject" "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to user@example.com"* ]]
  assert_himalaya_called "template send"
}

# ============================================================================
# HTML support
# ============================================================================

@test "send: passes text/plain content type by default" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send user@example.com "Subject" "$body"
  [ "$status" -eq 0 ]

  # Check that himalaya was called and the MML included text/plain
  # (the mock just logs args, the actual MML goes via stdin which we can't easily capture)
  assert_himalaya_called "template send"
}

@test "send: --html flag accepted" {
  local body="<h1>Hello</h1><p>This is an HTML email body that is definitely long enough to pass validation.</p>"
  run emails send user@example.com "Subject" --html "$body"
  [ "$status" -eq 0 ]
  assert_himalaya_called "template send"
}

# ============================================================================
# Body from file
# ============================================================================

@test "send: reads body from file path" {
  local body_file="$BATS_TEST_TMPDIR/body.txt"
  echo "This is a message body loaded from a file, long enough to pass the minimum length check." > "$body_file"
  run emails send user@example.com "Subject" "$body_file"
  [ "$status" -eq 0 ]
  assert_himalaya_called "template send"
}

# ============================================================================
# Body from stdin
# ============================================================================

@test "send: reads body from stdin" {
  local body="This is a message body piped via stdin that is definitely longer than fifty characters."
  run bash -c "cd '$REPO_DIR' && echo '$body' | GIT_AUTHOR_EMAIL='test-agent@ricon.family' HIMALAYA_CONFIG='$HIMALAYA_CONFIG' HIMALAYA='$HIMALAYA' PATH='$PATH' mise run -q send user@example.com 'Subject'"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Attachments
# ============================================================================

@test "send: rejects missing attachment file" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send user@example.com "Subject" "$body" -a /nonexistent/file.pdf
  [ "$status" -ne 0 ]
  [[ "$output" == *"Attachment not found"* ]]
}

@test "send: accepts valid attachment" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  local attach="$BATS_TEST_TMPDIR/doc.pdf"
  echo "fake pdf" > "$attach"
  run emails send user@example.com "Subject" "$body" -a "$attach"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Attaching: doc.pdf"* ]]
}

# ============================================================================
# GHL safety check
# ============================================================================

@test "send: rejects subject that looks like an email address" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send user@example.com candi@example.com "$body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"subject looks like an email address"* ]]
  [[ "$output" == *"--cc"* ]]
  [ ! -s "$MOCK_HIMALAYA_CALLS" ]
}

# ============================================================================
# Explicit --to / --subject flags
# ============================================================================

@test "send: --to and --subject flags work" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send --to user@example.com --subject "Explicit flags test" -b "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to user@example.com"* ]]
  assert_himalaya_called "template send"
}

@test "send: --to and --subject flags override positionals" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send positional@example.com "Positional subject" --to flag@example.com --subject "Flag subject" "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to flag@example.com"* ]]
}

@test "send: explicit --subject may look like an email address" {
  local body="This is a message body that is definitely longer than fifty characters for testing."
  run emails send --to user@example.com --subject candi@example.com -b "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to user@example.com"* ]]
  assert_himalaya_called "template send"
}

# ============================================================================
# --file structured input
# ============================================================================

@test "send: --file JSON input sends message" {
  local spec="$BATS_TEST_TMPDIR/email.json"
  cat > "$spec" <<'JSON'
{
  "to": "user@example.com",
  "subject": "File spec test",
  "body": "This is the message body loaded from the JSON file spec for structured agent email sending."
}
JSON
  run emails send --file "$spec"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to user@example.com"* ]]
  assert_himalaya_called "template send"
}

@test "send: --file JSON with cc array" {
  local spec="$BATS_TEST_TMPDIR/email-cc.json"
  cat > "$spec" <<'JSON'
{
  "to": "user@example.com",
  "subject": "CC file test",
  "body": "This is the message body loaded from the JSON file spec for CC testing in structured input.",
  "cc": ["alice@example.com", "bob@example.com"]
}
JSON
  run emails send --file "$spec"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cc:"* ]]
  [[ "$output" == *"alice@example.com"* ]]
}

@test "send: --file subject may look like an email address" {
  local spec="$BATS_TEST_TMPDIR/email-subject.json"
  cat > "$spec" <<'JSON'
{
  "to": "user@example.com",
  "subject": "candi@example.com",
  "body": "This is the message body loaded from the JSON file spec for structured agent email sending."
}
JSON
  run emails send --file "$spec"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Sent to user@example.com"* ]]
}

@test "send: --file rejects non-string body field" {
  local spec="$BATS_TEST_TMPDIR/email-bad-body.json"
  cat > "$spec" <<'JSON'
{
  "to": "user@example.com",
  "subject": "Bad body field",
  "body": ["not", "a", "string"]
}
JSON
  run emails send --file "$spec"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --file body field"* ]]
  [ ! -s "$MOCK_HIMALAYA_CALLS" ]
}

@test "send: --file rejects non-string cc entries" {
  local spec="$BATS_TEST_TMPDIR/email-bad-cc.json"
  cat > "$spec" <<'JSON'
{
  "to": "user@example.com",
  "subject": "Bad cc field",
  "body": "This is the message body loaded from the JSON file spec for structured agent email sending.",
  "cc": ["alice@example.com", 42]
}
JSON
  run emails send --file "$spec"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --file cc field"* ]]
  [ ! -s "$MOCK_HIMALAYA_CALLS" ]
}

@test "send: --file missing file errors" {
  run emails send --file /nonexistent/email.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"File not found"* ]]
}

@test "send: --file body and -b flag are mutually exclusive" {
  local spec="$BATS_TEST_TMPDIR/email-body.json"
  cat > "$spec" <<'JSON'
{
  "to": "user@example.com",
  "subject": "Conflict test",
  "body": "Body from file that is long enough to pass the minimum body length validation check."
}
JSON
  run emails send --file "$spec" -b "extra body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already provides a body"* ]]
}

# ============================================================================
# Identity
# ============================================================================

@test "send: fails without agent identity" {
  unset GIT_AUTHOR_EMAIL
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  echo "" > "$GIT_CONFIG_GLOBAL"
  local body="This is a message body that is definitely longer than fifty characters for testing."
  GIT_CONFIG_COUNT=0 run emails send user@example.com "Subject" "$body"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No agent identity"* ]]
}
