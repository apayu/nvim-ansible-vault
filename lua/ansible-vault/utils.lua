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
  return vim.api.nvim_buf_get_text(0, line_num - 1, 0, line_num, 0, {})[1]
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

return M
