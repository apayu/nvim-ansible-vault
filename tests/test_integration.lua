-- Integration test for vault file handling with missing password files
-- Run: nvim --headless -c "luafile tests/test_integration.lua" -c "qa"

local vault = require('ansible-vault')
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

local function assert_contains(haystack, needle)
  if not string.find(haystack, needle, 1, true) then
    error("Expected to find: '" .. needle .. "' in: '" .. haystack .. "'")
  end
end

local function assert_not_contains(haystack, needle)
  if string.find(haystack, needle, 1, true) then
    error("Did not expect to find: '" .. needle .. "' in: '" .. haystack .. "'")
  end
end

-- Create test environment
local tmp_dir = vim.fn.tempname()
vim.fn.mkdir(tmp_dir, "p")

-- Create only one password file out of three configured
local existing_password = tmp_dir .. "/.vault_password_dev"
vim.fn.writefile({"test_password"}, existing_password)

-- Create an encrypted vault file
local vault_content = [[
$ANSIBLE_VAULT;1.1;AES256
66386439653236336462626566316434353330386662643635306138363864316662323964616664
6132353431316131616134626462306139356663343065310a393736396136363764656436663634
62373764393838633030653366316639323566613962373231333331393566663938636363313734
3135306561356164310a636466356238303963633764626633643230336139323061613165383038
3161
]]
local vault_file = tmp_dir .. "/test_vault.yml"
vim.fn.writefile(vim.split(vault_content, "\n"), vault_file)

print("Testing vault file handling with missing password files...")

test("Setup with multiple identities where some files are missing", function()
  vault.setup({
    vault_identities = {
      { name = "prod", password_source = tmp_dir .. "/.vault_password_prod" },  -- Missing
      { name = "dev", password_source = existing_password },  -- Exists
      { name = "stage", password_source = tmp_dir .. "/.vault_password_stage" },  -- Missing
    }
  })
  
  -- Verify setup completed without errors
  assert(vault.config.vault_identities ~= nil)
end)

test("Get identities for file - normalizes all configured identities", function()
  local identities = vault.get_identities_for_file(vault_file)
  
  -- Should return all 3 identities regardless of file existence
  assert(#identities == 3)
  assert(identities[1].name == "prod")
  assert(identities[2].name == "dev")
  assert(identities[3].name == "stage")
end)

test("Build args without check - includes all identities", function()
  local identities = vault.get_identities_for_file(vault_file)
  local args = vault.build_ansible_vault_args(identities, false)
  
  -- Should include all vault-id arguments
  assert(#args == 6)  -- 3 identities * 2 args each (--vault-id, identity@path)
  assert_contains(table.concat(args, " "), "prod@")
  assert_contains(table.concat(args, " "), "dev@")
  assert_contains(table.concat(args, " "), "stage@")
end)

test("Build args with check - only includes existing files", function()
  local identities = vault.get_identities_for_file(vault_file)
  local args = vault.build_ansible_vault_args(identities, true)
  
  -- Should only include the dev identity
  assert(#args == 2)  -- 1 identity * 2 args (--vault-id, dev@path)
  assert_contains(table.concat(args, " "), "dev@")
  assert_not_contains(table.concat(args, " "), "prod@")
  assert_not_contains(table.concat(args, " "), "stage@")
end)

test("Simulated ansible-vault command with filtered args", function()
  local identities = vault.get_identities_for_file(vault_file)
  local args = {"echo", "ansible-vault", "view"}
  vim.list_extend(args, vault.build_ansible_vault_args(identities, true))
  table.insert(args, vault_file)
  
  local cmd = table.concat(args, " ")
  local output = vim.fn.system(cmd)
  
  -- Should only have one --vault-id argument for dev
  assert_contains(output, "--vault-id dev@")
  assert_not_contains(output, "--vault-id prod@")
  assert_not_contains(output, "--vault-id stage@")
end)

-- Cleanup
vim.fn.delete(tmp_dir, "rf")

print("✅ All integration tests passed!")