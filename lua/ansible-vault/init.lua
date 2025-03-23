local utils = require("ansible-vault.utils")

local M = {}

M.config = {
  vault_password_files = { ".vault_pass", ".vault-pass" },
  patterns = { "*/host_vars/*/vault.yml", "*/group_vars/*/vault.yml" },
  vault_id = "default",
}

M.encrypted_buffers = {}

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

  local encrypt_cmd = string.format(
    "ansible-vault encrypt --vault-id %s@%s --encrypt-vault-id %s %s",
    M.config.vault_id,
    info.password_file,
    M.config.vault_id,
    tmp
  )
  local result = vim.fn.system(encrypt_cmd)

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

function M.setup_buffer(buf, file_path, password_file)
  M.encrypted_buffers[buf] = {
    file_path = file_path,
    password_file = password_file,
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

function M.open_with_vault(file_path, password_file)
  local current_buf = vim.api.nvim_get_current_buf()

  local cmd = string.format("ansible-vault view --vault-password-file %s %s", password_file, file_path)
  local content = vim.fn.system(cmd)

  if vim.v.shell_error == 0 then
    local lines = vim.split(content, "\n")
    if lines[#lines] == "" then
      table.remove(lines)
    end

    vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, lines)

    M.setup_buffer(current_buf, file_path, password_file)

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

    local vault_pass = utils.find_vault_pass_file(file_path, M.config.vault_password_files)
    if vault_pass then
      vim.ui.select(
        { "Yes", "No" },
        { prompt = "This is an Ansible vault file. Open with vault password file?" },
        function(choice)
          if choice == "Yes" then
            M.open_with_vault(file_path, vault_pass)
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
    else
      vim.notify("No vault password file found in parent directories", vim.log.levels.WARN)
    end
  end
end

function M.encrypt_line(current_line_num, yaml_key, line_indent, yaml_value)
  if utils.is_encrypted_value(yaml_value) then
    vim.notify("Current value already encrypted", vim.log.levels.WARN)
    return false
  elseif utils.is_start_of_value_block(yaml_value) then
    vim.notify("This plugin does not support multiline encryption", vim.log.levels.WARN)
    return false
  end
  local vault_pass = utils.get_vault_pass_for_current_buffer(M.config.vault_password_files)
  if not vault_pass then
    vim.notify("Can not find vault password file for current buffer", vim.log.levels.WARN)
    return false
  end
  local encrypt_string_cmd = string.format(
    "ansible-vault encrypt_string --vault-id %s@%s --name='%s' '%s'",
    M.config.vault_id,
    vault_pass,
    yaml_key,
    yaml_value
  )
  local result = vim.fn.system(encrypt_string_cmd)
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
  local vault_pass = utils.get_vault_pass_for_current_buffer(M.config.vault_password_files)
  if not vault_pass then
    vim.notify("Can not find vault password file for current buffer", vim.log.levels.WARN)
    return false
  end
  local yaml_file = vim.fn.expand("%")
  local encrypt_string_cmd = string.format(
    "ansible localhost -m ansible.builtin.debug -a var='%s' -e '@%s' --vault-id %s@%s",
    yaml_key,
    yaml_file,
    M.config.vault_id,
    vault_pass
  )
  local result = vim.fn.system(encrypt_string_cmd)
  if vim.v.shell_error == 0 then
    vim.api.nvim_del_current_line() -- delete line with !vault
    vim.api.nvim_del_current_line() -- delete line with $ANSIBLE_VAULT
    while utils.extract_string_pattern(current_line_num, utils.pattern_hex_line) do
      vim.api.nvim_del_current_line() -- delete hex line
    end
    local raw_decrypted_value = vim.trim(vim.fn.split(result, "\n")[2])
    -- remove "" from yaml key
    local decrypted_value = string.gsub(raw_decrypted_value, '%s*"([a-z_]+)":%s+(.*)$', "%1: %2")
    vim.fn.append(current_line_num - 1, line_indent .. decrypted_value)
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

  local augroup = vim.api.nvim_create_augroup("AnsibleVault", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup,
    pattern = M.config.patterns,
    callback = function()
      M.handle_vault_file()
    end,
  })

  vim.api.nvim_create_user_command("AnsibleToggleVaultLine", M.toggle_line_encryption, {
    desc = "Toggle encryption in ansible yaml files",
  })
end

return M
