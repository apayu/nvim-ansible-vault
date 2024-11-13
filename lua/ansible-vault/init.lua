local M = {}

M.config = {
  vault_password_files = {'.vault_pass', '.vault-pass'},
  patterns = {'*/host_vars/*/vault.yml', '*/group_vars/*/vault.yml'},
  vault_id = 'default'
}

M.encrypted_buffers = {}

function M.is_vault_file(buf)
  local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  return first_line and first_line:match("^%$ANSIBLE_VAULT;") ~= nil
end

function M.find_vault_pass_file(path)
  if not path then return nil end

  local function find_project_root(start_path)
    local current_dir = vim.fn.fnamemodify(start_path, ':h')
    while current_dir ~= '/' do
      if vim.fn.isdirectory(current_dir .. '/.git') == 1 or
        vim.fn.filereadable(current_dir .. '/ansible.cfg') == 1 then
        return current_dir
      end
      current_dir = vim.fn.fnamemodify(current_dir, ':h')
    end
    return nil
  end

  local project_root = find_project_root(path)
  if not project_root then
    return nil
  end

  local check_locations = {
    project_root .. '/.vault_pass',
    project_root .. '/vault_pass',
    project_root .. '/group_vars/.vault_pass',
    project_root .. '/group_vars/vault_pass',
    project_root .. '/ansible.cfg'
  }

  for _, location in ipairs(check_locations) do
    if vim.fn.filereadable(location) == 1 then
      if vim.fn.fnamemodify(location, ':t') == 'ansible.cfg' then
        local lines = vim.fn.readfile(location)
        for _, line in ipairs(lines) do
          local vault_file = line:match("vault_password_file%s*=%s*(.+)")
          if vault_file then
            if not vault_file:match("^/") then
              vault_file = project_root .. '/' .. vault_file
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

  if M.config.vault_password_files then
    for _, file in ipairs(M.config.vault_password_files) do
      local vault_path = project_root .. '/' .. file
      if vim.fn.filereadable(vault_path) == 1 then
        return vault_path
      end
    end
  end

  return nil
end

function M.save_encrypted_file(buf, force)
  local info = M.encrypted_buffers[buf]
  if not info then
    vim.notify("Buffer information not found", vim.log.levels.ERROR)
    return false
  end

  if not force and not vim.api.nvim_buf_get_option(buf, 'modified') then
    vim.notify("No changes to save", vim.log.levels.INFO)
    return true
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(lines, tmp)

  local encrypt_cmd = string.format(
    'ansible-vault encrypt --vault-id %s@%s --encrypt-vault-id %s %s',
    M.config.vault_id, info.password_file, M.config.vault_id, tmp
  )
  local result = vim.fn.system(encrypt_cmd)

  if vim.v.shell_error == 0 then
    vim.fn.system(string.format('mv %s %s', tmp, info.file_path))
    vim.notify("File encrypted and saved", vim.log.levels.INFO)
    vim.api.nvim_buf_set_option(buf, 'modified', false)
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

function M.setup_buffer(buf, file_path, password_file)
  M.encrypted_buffers[buf] = {
    file_path = file_path,
    password_file = password_file
  }

  vim.api.nvim_buf_set_option(buf, 'buftype', 'acwrite')
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)

  local augroup = vim.api.nvim_create_augroup('AnsibleVaultBuffer' .. buf, { clear = true })

  vim.api.nvim_buf_create_user_command(buf, 'Write', function(opts)
    M.handle_write_cmd(opts)
  end, {bang = true, desc = 'Save encrypted vault file'})

  vim.api.nvim_create_autocmd("BufLeave", {
    group = augroup,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if M.encrypted_buffers[buf] and vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end
  })

  vim.api.nvim_create_autocmd({"BufWriteCmd", "FileWriteCmd"}, {
    group = augroup,
    buffer = buf,
    callback = function()
      return M.handle_write_cmd({})
    end
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = buf,
    callback = function()
      M.encrypted_buffers[buf] = nil
    end
  })
end

function M.open_with_vault(file_path, password_file)
  local current_buf = vim.api.nvim_get_current_buf()

  local cmd = string.format('ansible-vault view --vault-password-file %s %s', password_file, file_path)
  local content = vim.fn.system(cmd)

  if vim.v.shell_error == 0 then
    local lines = vim.split(content, '\n')
    if lines[#lines] == '' then
      table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, lines)

    M.setup_buffer(current_buf, file_path, password_file)

    vim.api.nvim_buf_set_option(current_buf, 'modified', false)

    vim.api.nvim_buf_set_option(current_buf, 'filetype', 'yaml')
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

    local vault_pass = M.find_vault_pass_file(file_path)
    if vault_pass then
      vim.ui.select(
        {'Yes', 'No'},
        {prompt = 'This is an Ansible vault file. Open with vault password file?'},
        function(choice)
          if choice == 'Yes' then
            M.open_with_vault(file_path, vault_pass)
          else
            local augroup = vim.api.nvim_create_augroup('AnsibleVaultDeclined' .. buf, { clear = true })
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
              once = true
            })
          end
        end
      )
    else
      vim.notify("No vault password file found in parent directories", vim.log.levels.WARN)
    end
  end
end

function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end

  local augroup = vim.api.nvim_create_augroup('AnsibleVault', { clear = true })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    pattern = M.config.patterns,
    callback = function()
      M.handle_vault_file()
    end
  })
end

return M
