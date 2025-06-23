local utils = require("ansible-vault.utils")

local M = {}

M.config = {
  vault_password_files = { ".vault_pass", ".vault-pass" },
  patterns = { "*/host_vars/*/vault.yml", "*/group_vars/*/vault.yml" },
  vault_id = "default",
}

M.encrypted_buffers = {}

-- Command building functions for vault-id support

--- Build ansible vault arguments from identities
--- @param identities table List of identity objects
--- @return table args List of command arguments
function M.build_ansible_vault_args(identities)
  local args = {}
  
  for _, identity in ipairs(identities) do
    if identity.password_source then
      table.insert(args, "--vault-id")
      table.insert(args, identity.name .. "@" .. identity.password_source)
    end
  end
  
  return args
end

--- Get available vault identities from config
--- @param file_path string Optional file path for legacy mode
--- @return table identities List of available identity objects
function M.get_available_identities(file_path)
  if M.config.vault_identities then
    return utils.normalize_vault_identities(M.config, file_path)
  else
    -- Fallback to old format
    local legacy_identities = {}
    if M.config.vault_password_files then
      for _, file in ipairs(M.config.vault_password_files) do
        local vault_pass = utils.get_vault_pass_for_current_buffer(M.config.vault_password_files)
        if vault_pass then
          table.insert(legacy_identities, {
            name = M.config.vault_id or "default",
            password_source = vault_pass
          })
          break
        end
      end
    end
    return legacy_identities
  end
end

--- Get default identity
--- @param file_path string Optional file path for legacy mode
--- @return table|nil identity Default identity object or nil
function M.get_default_identity(file_path)
  local identities = M.get_available_identities(file_path)
  if #identities > 0 then
    return identities[1]
  end
  return nil
end

--- Detect required identities for a file (placeholder for now)
--- @param file_path string Path to the file
--- @return table identities List of required identity objects
function M.get_identities_for_file(file_path)
  -- For now, just return all available identities
  -- TODO: Implement actual detection based on file content
  local available = M.get_available_identities(file_path)
  if #available > 0 then
    return available
  end
  
  -- Fallback to default
  local default = M.get_default_identity(file_path)
  return default and { default } or {}
end

function M.is_vault_file(buf)
  local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  return first_line and first_line:match("^%$ANSIBLE_VAULT;") ~= nil
end

function M.save_encrypted_file(buf, force)
  local info = M.encrypted_buffers[buf]
  if not info then
    vim.notify("Buffer information not found", vim.log.levels.ERROR)
    return false
  end

  if not force and not vim.api.nvim_buf_get_option(buf, "modified") then
    vim.notify("No changes to save", vim.log.levels.INFO)
    return true
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(lines, tmp)

  local args = {"ansible-vault", "encrypt"}
  vim.list_extend(args, M.build_ansible_vault_args(info.identities))
  table.insert(args, "--encrypt-vault-id")
  table.insert(args, info.default_identity.name)
  table.insert(args, tmp)
  
  local result = vim.fn.system(args)

  if vim.v.shell_error == 0 then
    vim.fn.system(string.format("mv %s %s", tmp, info.file_path))
    vim.notify("File encrypted and saved", vim.log.levels.INFO)
    vim.api.nvim_buf_set_option(buf, "modified", false)
    return true
  else
    vim.notify("Failed to encrypt file: " .. result, vim.log.levels.ERROR)
    vim.fn.delete(tmp)
    return false
  end
end

function M.handle_write_cmd(opts)
  local buf = vim.api.nvim_get_current_buf()
  local force = opts and opts.bang
  return M.save_encrypted_file(buf, force)
end

function M.setup_buffer(buf, file_path, identities)
  M.encrypted_buffers[buf] = {
    file_path = file_path,
    identities = identities,
    default_identity = identities[1] or M.get_default_identity(file_path),
  }

  vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  local augroup = vim.api.nvim_create_augroup("AnsibleVaultBuffer" .. buf, { clear = true })

  vim.api.nvim_buf_create_user_command(buf, "Write", function(opts)
    M.handle_write_cmd(opts)
  end, { bang = true, desc = "Save encrypted vault file" })

  vim.api.nvim_create_autocmd("BufLeave", {
    group = augroup,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if M.encrypted_buffers[buf] and vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWriteCmd", "FileWriteCmd" }, {
    group = augroup,
    buffer = buf,
    callback = function()
      return M.handle_write_cmd({})
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = buf,
    callback = function()
      M.encrypted_buffers[buf] = nil
    end,
  })
end

function M.open_with_vault(file_path, identities)
  local current_buf = vim.api.nvim_get_current_buf()

  local args = {"ansible-vault", "view"}
  vim.list_extend(args, M.build_ansible_vault_args(identities))
  table.insert(args, file_path)
  
  local content = vim.fn.system(args)

  if vim.v.shell_error == 0 then
    local lines = vim.split(content, "\n")
    if lines[#lines] == "" then
      table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, lines)

    M.setup_buffer(current_buf, file_path, identities)

    vim.api.nvim_buf_set_option(current_buf, "modified", false)

    vim.api.nvim_buf_set_option(current_buf, "filetype", "yaml")
  else
    vim.notify("Failed to decrypt file: " .. content, vim.log.levels.ERROR)
  end
end

function M.handle_vault_file()
  local buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(buf)

  if M.is_vault_file(buf) then
    if M.encrypted_buffers[buf] then
      return
    end

    local identities = M.get_identities_for_file(file_path)
    if #identities > 0 then
      vim.ui.select(
        { "Yes", "No" },
        { prompt = "This is an Ansible vault file. Open with vault identities?" },
        function(choice)
          if choice == "Yes" then
            M.open_with_vault(file_path, identities)
          else
            local augroup = vim.api.nvim_create_augroup("AnsibleVaultDeclined" .. buf, { clear = true })
            vim.api.nvim_create_autocmd("BufLeave", {
              group = augroup,
              buffer = buf,
              callback = function()
                vim.schedule(function()
                  if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                  end
                end)
              end,
              once = true,
            })
          end
        end
      )
    end
    -- Silently ignore if no identities found, like the original version
  end
end

function M.encrypt_line(current_line_num, yaml_key, line_indent, yaml_value, identity)
  if utils.is_encrypted_value(yaml_value) then
    vim.notify("Current value already encrypted", vim.log.levels.WARN)
    return false
  elseif utils.is_start_of_value_block(yaml_value) then
    vim.notify("This plugin does not support multiline encryption", vim.log.levels.WARN)
    return false
  end
  
  identity = identity or M.get_default_identity(vim.fn.expand("%:p"))
  if not identity then
    vim.notify("No vault identity available for encryption", vim.log.levels.WARN)
    return false
  end
  
  local args = {
    "ansible-vault", "encrypt_string",
    "--vault-id", identity.name .. "@" .. identity.password_source,
    "--name", yaml_key,
    yaml_value
  }
  
  local result = vim.fn.system(args)
  if vim.v.shell_error == 0 then
    vim.api.nvim_del_current_line()
    local f_indent_line = function(line)
      return line_indent .. line
    end
    local lines_with_indentation = vim.tbl_map(f_indent_line, vim.fn.split(result, "\n"))
    vim.fn.append(current_line_num - 1, lines_with_indentation)
    vim.fn.setpos(".", { 0, current_line_num, 0 })
    return true
  end
  vim.notify("Can not encrypt string: " .. result, vim.log.levels.ERROR)
  return false
end

function M.decrypt_line(current_line_num, yaml_key, line_indent, yaml_value)
  if not utils.is_encrypted_value(yaml_value) then
    vim.notify("Is not encrypted value", vim.log.levels.WARN)
    return false
  end
  
  local yaml_file = vim.fn.expand("%")
  local identities = M.get_identities_for_file(yaml_file)
  
  if #identities == 0 then
    vim.notify("No vault identities found for current file", vim.log.levels.ERROR)
    return false
  end
  
  local args = {
    "ansible", "localhost",
    "-m", "ansible.builtin.debug",
    "-a", "var='" .. yaml_key .. "'",
    "-e", "@" .. yaml_file
  }
  
  vim.list_extend(args, M.build_ansible_vault_args(identities))
  
  local result = vim.fn.system(args)
  if vim.v.shell_error == 0 then
    vim.api.nvim_del_current_line() -- delete line with !vault
    vim.api.nvim_del_current_line() -- delete line with $ANSIBLE_VAULT
    while utils.extract_string_pattern(current_line_num, utils.pattern_hex_line) do
      vim.api.nvim_del_current_line() -- delete hex line
    end
    -- Parse ansible output which is in format:
    -- localhost | SUCCESS => {
    --     "key": "value"
    -- }
    local lines = vim.fn.split(result, "\n")
    local decrypted_value = nil
    
    -- Method 1: Try to find the line with our key
    for i, line in ipairs(lines) do
      local trimmed = vim.trim(line)
      -- Match patterns like: "key": "value" or "key": value
      local value = trimmed:match('^"' .. yaml_key .. '":%s*"([^"]*)"')
      if not value then
        value = trimmed:match('^"' .. yaml_key .. '":%s*([^,}]+)')
      end
      if value then
        decrypted_value = vim.trim(value)
        break
      end
    end
    
    -- Method 2: If that fails, try parsing the JSON output
    if not decrypted_value then
      -- Extract JSON part (everything after =>)
      local json_part = result:match("=>%s*({.-})")
      if json_part then
        -- Try to decode JSON
        local ok, decoded = pcall(vim.fn.json_decode, json_part)
        if ok and decoded and decoded[yaml_key] then
          decrypted_value = decoded[yaml_key]
        end
      end
    end
    
    if not decrypted_value then
      vim.notify("Could not parse decrypted value from ansible output:\n" .. result, vim.log.levels.ERROR)
      return false
    end
    
    -- Format as YAML line
    local formatted_line = yaml_key .. ": " .. decrypted_value
    vim.fn.append(current_line_num - 1, line_indent .. formatted_line)
    vim.fn.setpos(".", { 0, current_line_num, 0 })
    return true
  end
  vim.notify("Can not decrypt string: " .. result, vim.log.levels.ERROR)
  return false
end

function M.toggle_line_encryption()
  local current_line_num, yaml_key, line_indent = utils.parse_current_line_to_extract_key_and_indent()
  if current_line_num == nil or yaml_key == nil then
    return nil
  end
  local yaml_value = utils.get_yaml_value_for_the_line(current_line_num, yaml_key)
  if not yaml_value then
    vim.notify("Can not get yaml value for the current line", vim.log.levels.WARN)
    return false
  end
  if utils.is_encrypted_value(yaml_value) then
    M.decrypt_line(current_line_num, yaml_key, line_indent, yaml_value)
  else
    M.encrypt_line(current_line_num, yaml_key, line_indent, yaml_value)
  end
end

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  -- Validate vault identities configuration format only
  if M.config.vault_identities then
    for i, identity_config in ipairs(M.config.vault_identities) do
      if type(identity_config) == "string" then
        local identity, password_source, error_msg = utils.parse_vault_id_format(identity_config)
        if error_msg then
          vim.notify("Vault ID configuration error at " .. i .. ": " .. error_msg, vim.log.levels.ERROR)
          return
        end
      elseif type(identity_config) == "table" then
        if not identity_config.name then
          vim.notify("Vault ID configuration error at " .. i .. ": missing name", vim.log.levels.ERROR)
          return
        end
        if not identity_config.password_source then
          vim.notify("Vault ID configuration error at " .. i .. ": missing password_source", vim.log.levels.ERROR)
          return
        end
      else
        vim.notify("Vault ID configuration error at " .. i .. ": invalid format", vim.log.levels.ERROR)
        return
      end
    end
  end

  local augroup = vim.api.nvim_create_augroup("AnsibleVault", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    pattern = M.config.patterns,
    callback = function()
      M.handle_vault_file()
    end,
  })

end

return M
