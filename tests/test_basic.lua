-- Simple test for vault-id parsing
-- Run: nvim --headless -c "luafile tests/test_basic.lua" -c "qa"

local utils = require('ansible-vault.utils')

local function test(description, fn)
  local ok, err = pcall(fn)
  if ok then
    print("✓ " .. description)
  else
    print("✗ " .. description .. " - " .. tostring(err))
    os.exit(1)
  end
end

local function assert_eq(actual, expected)
  if actual ~= expected then
    error("Expected: " .. tostring(expected) .. ", Got: " .. tostring(actual))
  end
end

print("Testing vault-id parsing...")

test("Basic format parsing", function()
  local identity, source, err = utils.parse_vault_id_format("dev@.vault_pass")
  assert_eq(identity, "dev")
  assert_eq(source, ".vault_pass")
  assert_eq(err, nil)
end)

test("Identity with @ symbol", function()
  local identity, source, err = utils.parse_vault_id_format("user@domain.com@password_file")
  assert_eq(identity, "user@domain.com")
  assert_eq(source, "password_file")
  assert_eq(err, nil)
end)

test("Empty identity error", function()
  local identity, source, err = utils.parse_vault_id_format("@invalid")
  assert_eq(identity, nil)
  assert_eq(err, "Empty identity name")
end)

test("Path resolution", function()
  local resolved = utils.resolve_password_source_path("/absolute/path", "/base")
  assert_eq(resolved, "/absolute/path")
end)

print("✅ All tests passed!")