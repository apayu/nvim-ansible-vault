# nvim-ansible-vault

A lightweight and simple Neovim plugin for handling Ansible vault encrypted files.

## Features

- Automatically detects Ansible vault encrypted files
- Multiple vault identity support
- vault-id@script format support
- Supports saving encrypted files with `:w` command
- Custom vault password file patterns

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "apayu/nvim-ansible-vault",
    config = function()
        require("ansible-vault").setup({
            vault_identities = {
                "dev@.vault_pass_dev",
                "prod@./get_prod_password.sh"
            }
        })
    end,
    event = "BufReadPre */vault.yml",
}
```

## Configuration

### Multiple Vault Identities

```lua
require("ansible-vault").setup({
    vault_identities = {
        "dev@.vault_pass_dev",              -- File password
        "prod@./get_prod_password.sh",      -- Script password
        {                                   -- Object format
            name = "staging",
            password_source = ".vault_pass_staging"
        }
    }
})
```

### Single Vault Password

```lua
require("ansible-vault").setup({
    vault_password_files = {'.vault_pass', '.vault-pass'},
    vault_id = 'default'
})
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

## vault-id@script Format

The plugin supports Ansible's `vault-id@password-source` format:

```lua
vault_identities = {
    "dev@.vault_pass_dev",           -- identity "dev" with file password
    "prod@./get_password.sh",        -- identity "prod" with script password
    "staging@/path/to/script"        -- identity "staging" with absolute script path
}
```

When using scripts, ensure they:
- Are executable (`chmod +x script.sh`)
- Output the password to stdout
- Exit with code 0 on success

## Testing

Run the test suite:

```bash
./tests/run.sh
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
