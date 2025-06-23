local M = {}

M.pattern_yaml_key = "^%s*([a-zA-Z0-9][a-zA-Z0-9_]+):.+$"
M.pattern_sting_indent = "^(%s).*$"
M.pattern_hex_line = "^%s*([0-9a-f]+)$"

function M.find_vault_pass_file(path, vault_password_files)
  if not path then
    return nil
  end

  local function find_project_root(start_path)
    local current_dir = vim.fn.fnamemodify(start_path, ":h")
    while current_dir ~= "/" do
      if
        vim.fn.isdirectory(current_dir .. "/.git") == 1
        or vim.fn.filereadable(current_dir .. "/ansible.cfg") == 1
      then
        return current_dir
      end
      current_dir = vim.fn.fnamemodify(current_dir, ":h")
    end
    return nil
  end

  local project_root = find_project_root(path)
  if not project_root then
    return nil
  end

  local check_locations = {
    project_root .. "/.vault_pass",
    project_root .. "/vault_pass",
    project_root .. "/group_vars/.vault_pass",
    project_root .. "/group_vars/vault_pass",
    project_root .. "/ansible.cfg",
  }

  for _, location in ipairs(check_locations) do
    if vim.fn.filereadable(location) == 1 then
      if vim.fn.fnamemodify(location, ":t") == "ansible.cfg" then
        local lines = vim.fn.readfile(location)
        for _, line in ipairs(lines) do
          local vault_file = line:match("vault_password_file%s*=%s*(.+)")
          if vault_file then
            if not vault_file:match("^/") then
              vault_file = project_root .. "/" .. vault_file
            end
            if vim.fn.filereadable(vault_file) == 1 then
              return vault_file
            end
          end
        end
      else
        return location
      end
    end
  end

  if vault_password_files then
    for _, file in ipairs(vault_password_files) do
      local vault_path = project_root .. "/" .. file
      if vim.fn.filereadable(vault_path) == 1 then
        return vault_path
      end
    end
  end

  return nil
end

function M.get_a_line_content(line_num)
  if not tonumber(line_num) then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(0)
  if line_num < 1 or line_num > line_count then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)
  return lines[1]
end

function M.is_start_of_value_block(yaml_value)
  if yaml_value and string.find(yaml_value, "[>|][-]?$") and string.find(yaml_value, "\\") then
    return true
  end
  return false
end

function M.is_encrypted_value(yaml_value)
  if yaml_value and string.find(vim.trim(yaml_value), "^!vault") then
    return true
  end
  return false
end

function M.extract_string_pattern(line_num, pattern)
  if not tonumber(line_num) then
    return nil
  end
  local line_content = M.get_a_line_content(line_num)
  if not line_content then
    return nil
  end
  local match = string.match(line_content, pattern)
  return match
end

function M.get_yaml_value_for_the_line(line_num, yaml_key)
  local line_content = M.get_a_line_content(line_num)
  if not line_content then
    return nil
  end
  local _, idx_end = string.find(line_content, yaml_key)
  if not idx_end then
    return nil
  end
  local yaml_value = vim.trim(string.sub(line_content, idx_end + 2))
  if not yaml_value or string.len(yaml_value) == 0 then
    return nil
  end
  return yaml_value
end

function M.parse_current_line_to_extract_key_and_indent()
  local current_line_num = vim.fn.line(".")
  local yaml_key = M.extract_string_pattern(current_line_num, M.pattern_yaml_key)
  if not yaml_key then
    vim.notify("Can not read yaml key for the current line", vim.log.levels.WARN)
    return nil
  end
  local line_indent = M.extract_string_pattern(current_line_num, M.pattern_sting_indent) or ""
  return current_line_num, yaml_key, line_indent
end

function M.get_vault_pass_for_current_buffer(vault_password_files)
  local buf = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(buf)
  if not file_path then
    return nil
  end
  return M.find_vault_pass_file(file_path, vault_password_files)
end

-- Vault ID format parsing functions

--- Parse vault-id@password-source format
--- @param vault_id_string string The vault ID string to parse
--- @return string|nil identity The vault identity name
--- @return string|nil password_source The password source path
--- @return string|nil error_msg Error message if parsing failed
function M.parse_vault_id_format(vault_id_string)
  if not vault_id_string or vault_id_string == "" then
    return nil, nil, "Empty vault ID string"
  end
  
  -- Find the last @ symbol (allows identity names to contain @)
  local at_pos = vault_id_string:find("@[^@]*$")
  if not at_pos then
    -- No @ symbol, treat as pure identity name
    return vault_id_string, nil, nil
  end
  
  local identity = vault_id_string:sub(1, at_pos - 1)
  local password_source = vault_id_string:sub(at_pos + 1)
  
  -- Validate identity name
  if identity == "" then
    return nil, nil, "Empty identity name"
  end
  
  -- Validate password source
  if password_source == "" then
    return nil, nil, "Empty password source"
  end
  
  return identity, password_source, nil
end

--- Resolve password source path (handle relative and absolute paths)
--- @param password_source string The password source from parsing
--- @param base_path string Base path for relative resolution
--- @return string resolved_path The absolute path to password source
function M.resolve_password_source_path(password_source, base_path)
  if not password_source then
    return nil
  end
  
  if not base_path then
    base_path = vim.fn.getcwd()
  end
  
  -- Handle absolute path
  if password_source:sub(1, 1) == "/" then
    return password_source
  end
  
  -- Handle relative path starting with ./
  if password_source:sub(1, 2) == "./" then
    return vim.fn.fnamemodify(base_path .. "/" .. password_source:sub(3), ":p")
  end
  
  -- Handle relative path
  return vim.fn.fnamemodify(base_path .. "/" .. password_source, ":p")
end

--- Validate vault ID configuration
--- @param config table Configuration table to validate
--- @return boolean valid True if configuration is valid
--- @return table errors List of error messages
function M.validate_vault_id_config(config)
  local errors = {}
  
  if not config then
    table.insert(errors, "Configuration is nil")
    return false, errors
  end
  
  if config.vault_identities then
    for i, identity_config in ipairs(config.vault_identities) do
      if type(identity_config) == "string" then
        -- Parse string format
        local identity, password_source, error_msg = M.parse_vault_id_format(identity_config)
        if error_msg then
          table.insert(errors, "Identity " .. i .. ": " .. error_msg)
        elseif password_source then
          -- Validate password source exists
          local resolved_path = M.resolve_password_source_path(password_source, vim.fn.getcwd())
          if not vim.fn.filereadable(resolved_path) and vim.fn.executable(resolved_path) == 0 then
            table.insert(errors, "Identity " .. identity .. ": password source not found or not accessible: " .. resolved_path)
          end
        end
      elseif type(identity_config) == "table" then
        -- Validate object format
        if not identity_config.name then
          table.insert(errors, "Identity " .. i .. ": missing name")
        end
        if not identity_config.password_source then
          table.insert(errors, "Identity " .. i .. ": missing password_source")
        else
          local resolved_path = M.resolve_password_source_path(identity_config.password_source, vim.fn.getcwd())
          if not vim.fn.filereadable(resolved_path) and vim.fn.executable(resolved_path) == 0 then
            table.insert(errors, "Identity " .. identity_config.name .. ": password source not found or not accessible: " .. resolved_path)
          end
        end
      else
        table.insert(errors, "Identity " .. i .. ": invalid format (must be string or table)")
      end
    end
  end
  
  return #errors == 0, errors
end

--- Normalize vault identities configuration
--- Convert string format to object format for consistent handling
--- @param config table Configuration table
--- @return table normalized_identities List of normalized identity objects
function M.normalize_vault_identities(config)
  local normalized = {}
  
  if not config or not config.vault_identities then
    return normalized
  end
  
  for _, identity_config in ipairs(config.vault_identities) do
    if type(identity_config) == "string" then
      -- Parse string format and convert to object format
      local identity, password_source, error_msg = M.parse_vault_id_format(identity_config)
      if not error_msg then
        local normalized_item = {
          name = identity,
          password_source = password_source and M.resolve_password_source_path(password_source, vim.fn.getcwd()) or nil,
          raw_format = identity_config
        }
        table.insert(normalized, normalized_item)
      end
    elseif type(identity_config) == "table" then
      -- Already object format, just resolve the path
      local normalized_item = vim.tbl_deep_extend("force", {}, identity_config)
      if normalized_item.password_source then
        normalized_item.password_source = M.resolve_password_source_path(normalized_item.password_source, vim.fn.getcwd())
      end
      table.insert(normalized, normalized_item)
    end
  end
  
  return normalized
end

--- Find project root directory for path resolution
--- @param start_path string Starting path for search
--- @return string|nil project_root The project root directory or nil if not found
function M.find_project_root(start_path)
  if not start_path then
    start_path = vim.fn.expand("%:p")
  end
  
  local current_dir = vim.fn.fnamemodify(start_path, ":h")
  while current_dir ~= "/" do
    if vim.fn.isdirectory(current_dir .. "/.git") == 1
       or vim.fn.filereadable(current_dir .. "/ansible.cfg") == 1
       or vim.fn.filereadable(current_dir .. "/playbook.yml") == 1
       or vim.fn.filereadable(current_dir .. "/site.yml") == 1 then
      return current_dir
    end
    current_dir = vim.fn.fnamemodify(current_dir, ":h")
  end
  return nil
end

return M
