-- Test for build_ansible_vault_args function with file existence checking
-- Run: nvim --headless -c "luafile tests/test_build_ansible_vault_args.lua" -c "qa"

local vault = require('ansible-vault')

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

local function assert_table_eq(actual, expected)
  if #actual ~= #expected then
    error("Table length mismatch. Expected: " .. #expected .. ", Got: " .. #actual)
  end
  for i = 1, #expected do
    if actual[i] ~= expected[i] then
      error("Element " .. i .. " mismatch. Expected: " .. tostring(expected[i]) .. ", Got: " .. tostring(actual[i]))
    end
  end
end

-- Create temporary test files
local tmp_dir = vim.fn.tempname()
vim.fn.mkdir(tmp_dir, "p")
local existing_file = tmp_dir .. "/existing.vault"
local missing_file = tmp_dir .. "/missing.vault"
vim.fn.writefile({"test"}, existing_file)

print("Testing build_ansible_vault_args...")

test("Without check_exists - includes all identities", function()
  local identities = {
    { name = "dev", password_source = existing_file },
    { name = "prod", password_source = missing_file },
    { name = "test", password_source = nil },  -- No password source
  }
  
  local args = vault.build_ansible_vault_args(identities, false)
  assert_table_eq(args, {
    "--vault-id", "dev@" .. existing_file,
    "--vault-id", "prod@" .. missing_file,
  })
end)

test("With check_exists - only includes existing files", function()
  local identities = {
    { name = "dev", password_source = existing_file },
    { name = "prod", password_source = missing_file },
    { name = "stage", password_source = "/non/existent/path" },
  }
  
  local args = vault.build_ansible_vault_args(identities, true)
  assert_table_eq(args, {
    "--vault-id", "dev@" .. existing_file,
  })
end)

test("Empty identities list", function()
  local identities = {}
  local args = vault.build_ansible_vault_args(identities, true)
  assert_eq(#args, 0)
end)

test("All missing files with check_exists", function()
  local identities = {
    { name = "prod", password_source = missing_file },
    { name = "stage", password_source = "/non/existent/path" },
  }
  
  local args = vault.build_ansible_vault_args(identities, true)
  assert_eq(#args, 0)
end)

test("Identities without password_source are skipped", function()
  local identities = {
    { name = "dev" },  -- No password_source
    { name = "prod", password_source = existing_file },
  }
  
  local args = vault.build_ansible_vault_args(identities, false)
  assert_table_eq(args, {
    "--vault-id", "prod@" .. existing_file,
  })
end)

-- Cleanup
vim.fn.delete(tmp_dir, "rf")

print("✅ All tests passed!")