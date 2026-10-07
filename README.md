# yaml.nvim

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

A Neovim plugin that exposes a full-featured YAML parsing API for Lua -- read, write, and manipulate YAML safely inside Neovim.

## Features

- 🔍 **Parse YAML**: Convert YAML strings and files to Lua tables
- ✍️ **Encode YAML**: Convert Lua tables to YAML strings
- 📁 **File I/O**: Read from and write to YAML files
- 🔧 **Manipulation**: Safely modify YAML files with helper functions
- 🛡️ **Safe**: Error handling for all operations
- 🚀 **Fast**: Pure Lua implementation, no external dependencies

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use 'jedi-knights/yaml.nvim'
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ 'jedi-knights/yaml.nvim' }
```

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'jedi-knights/yaml.nvim'
```

The plugin is the single file `lua/yaml.lua`, which has no dependencies. You can
also copy it into your own configuration or plugin and load it with `require`.

## Usage

### Parsing YAML

#### Parse a YAML string

```lua
local yaml = require('yaml')

local yaml_string = [[
name: John Doe
age: 30
hobbies:
  - reading
  - coding
]]

local data, err = yaml.parse(yaml_string)
if data then
  print(data.name)  -- "John Doe"
  print(data.age)   -- 30
  print(data.hobbies[1])  -- "reading"
else
  print("Error:", err)
end
```

#### Read a YAML file

```lua
local yaml = require('yaml')

local data, err = yaml.read('config.yaml')
if data then
  print(vim.inspect(data))
else
  print("Error:", err)
end
```

### Encoding YAML

#### Encode a Lua table to YAML

```lua
local yaml = require('yaml')

local data = {
  name = "Jane Doe",
  age = 25,
  settings = {
    theme = "dark",
    notifications = true
  }
}

local yaml_string = yaml.encode(data)
print(yaml_string)
-- Output:
-- age: 25
-- name: Jane Doe
-- settings:
--   notifications: true
--   theme: dark
```

#### Write to a YAML file

```lua
local yaml = require('yaml')

local data = {
  version = 1,
  config = {
    enabled = true
  }
}

local success, err = yaml.write('output.yaml', data)
if success then
  print("File written successfully")
else
  print("Error:", err)
end
```

### Manipulating YAML

#### Modify a YAML file

```lua
local yaml = require('yaml')

local success, err = yaml.modify('config.yaml', function(data)
  data.version = 2
  data.updated_at = os.date("%Y-%m-%d")
  return data
end)
```

#### Get nested values

```lua
local yaml = require('yaml')

local data = {
  database = {
    host = "localhost",
    port = 5432
  }
}

local host = yaml.get(data, "database.host")  -- "localhost"
local port = yaml.get(data, "database.port")  -- 5432
```

#### Set nested values

```lua
local yaml = require('yaml')

local data = {}
yaml.set(data, "database.host", "localhost")
yaml.set(data, "database.port", 5432)

-- data is now:
-- {
--   database = {
--     host = "localhost",
--     port = 5432
--   }
-- }
```

## API Reference

### `yaml.parse(content)`

Parse a YAML string into a Lua table.

**Parameters:**
- `content` (string): The YAML content to parse

**Returns:**
- `table|nil`: The parsed YAML as a Lua table, or nil on error
- `string|nil`: Error message if parsing failed

### `yaml.read(filepath)`

Read and parse a YAML file.

**Parameters:**
- `filepath` (string): Path to the YAML file

**Returns:**
- `table|nil`: The parsed YAML as a Lua table, or nil on error
- `string|nil`: Error message if reading/parsing failed

### `yaml.encode(data, options)`

Encode a Lua table to a YAML string.

**Parameters:**
- `data` (table): The Lua table to encode
- `options` (table, optional): Encoding options
  - `indent_width` (integer): Number of spaces per indentation level (default: 2)

**Returns:**
- `string`: The YAML string

### `yaml.write(filepath, data, options)`

Write a Lua table to a YAML file.

**Parameters:**
- `filepath` (string): Path to the output file
- `data` (table): The Lua table to encode
- `options` (table, optional): Encoding options, as for `yaml.encode`

**Returns:**
- `boolean`: Success status
- `string|nil`: Error message if writing failed

### `yaml.modify(filepath, modifier, options)`

Load, modify, and save a YAML file.

**Parameters:**
- `filepath` (string): Path to the YAML file
- `modifier` (function): Function that takes and returns a table
- `options` (table, optional): Encoding options used when saving, as for `yaml.encode`

**Returns:**
- `boolean`: Success status
- `string|nil`: Error message if operation failed

### `yaml.get(data, path)`

Safely access nested values using dot notation.

**Parameters:**
- `data` (table): The table to query
- `path` (string): Dot-separated path (e.g., "database.host")

**Returns:**
- `any`: The value at the path, or nil if not found

### `yaml.set(data, path, value)`

Safely set nested values using dot notation.

**Parameters:**
- `data` (table): The table to modify
- `path` (string): Dot-separated path (e.g., "database.host")
- `value` (any): The value to set

**Returns:**
- `table`: The modified table

## Supported YAML Features

- ✅ Key-value pairs
- ✅ Nested objects
- ✅ Arrays/Lists, including lists of objects and nested lists
- ✅ Strings (plain, single-quoted, and double-quoted with escapes)
- ✅ Numbers (integers, floats, `.inf`, `.nan`)
- ✅ Booleans
- ✅ Null values
- ✅ Empty collections (`[]` and `{}`)
- ✅ Comments (ignored during parsing)
- ✅ Multi-line strings (literal `|` and folded `>`, with chomping indicators)

`yaml.encode` output reads back as the same data with `yaml.parse` and with
other YAML parsers. Strings that YAML 1.1 parsers would read as another type
(for example `yes`, `1_000`, or `2001-12-14`) are quoted.

Not supported: flow collections other than `[]` and `{}`, anchors and aliases,
tags, multiple documents, and plain or quoted strings that span several lines.
`yaml.parse` returns `nil` and an error message naming the line when it meets
these or any other invalid input.

## Testing

Run tests using:

```bash
make test
```

Or manually:

```bash
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

## License

MIT License - see LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
