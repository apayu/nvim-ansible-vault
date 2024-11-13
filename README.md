# nvim-ansible-vault

A Neovim plugin for handling Ansible vault encrypted files.

## Features

- Automatically detects Ansible vault encrypted files
- Decrypts vault files using vault password file
- Supports saving encrypted files with `:w` command
- Maintains encryption when saving files
- Supports custom vault password file patterns
- Integrates with Ansible vault commands

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "apayu/nvim-ansible-vault",
    config = function()
        require("ansible-vault").setup({
            -- Optional custom configuration
            vault_password_files = {'.vault_pass', '.vault-pass'},
            patterns = {'*/host_vars/*/vault.yml', '*/group_vars/*/vault.yml'},
            vault_id = 'default'
        })
    end,
    event = "BufReadPre */vault.yml",  -- Load only when opening vault files
}
```

## Configuration

Default configuration:

```lua
{
    -- Patterns for vault password files to look for
    vault_password_files = {'.vault_pass', '.vault-pass'},

    -- File patterns to trigger the plugin
    patterns = {'*/host_vars/*/vault.yml', '*/group_vars/*/vault.yml'},

    -- Default vault ID to use
    vault_id = 'default'
}
```

## Requirements

- Neovim >= 0.8.0
- Ansible vault command line tool

## Usage

1. Place your vault password in a `.vault_pass` or `.vault-pass` file in your project directory
2. Open an encrypted vault file
3. The plugin will automatically detect and decrypt the file
4. Edit the file normally
5. Save with `:w` to encrypt and save the file

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
