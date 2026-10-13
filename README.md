# yaml.nvim

A YAML parser and encoder for Lua, in one file: [`lua/yaml.lua`](lua/yaml.lua).
It has no dependencies, so you can copy it into your plugin, and your users
don't need to install anything extra.

The file needs only the Lua standard library. Tests cover LuaJIT 2.1 (the Lua
in Neovim), Lua 5.2, and Lua 5.4. The module keeps no global state and has no
`setup` function. Every option is passed as an argument, so several plugins
can each ship their own copy without interfering with each other.

## Adding it to your plugin

Copy the file into your plugin's namespace:

```sh
curl -fLo lua/myplugin/yaml.lua \
  https://raw.githubusercontent.com/cvigilv/yaml.nvim/main/lua/yaml.lua
```

Then load it from there:

```lua
local yaml = require("myplugin.yaml")
```

Keep the license header at the top of the file. It's what the MIT license asks
of copies.

Putting the file under your own namespace avoids clashing with any other
module named `yaml`. You can also install this repository as a regular Neovim
plugin and use `require("yaml")`. Then your users need to install it too.

## Usage

### Parsing

```lua
local data, err = yaml.parse([[
name: demo
servers:
  - host: alpha.example.com
    port: 8080
  - host: beta.example.com
    port: 8081
]])

print(data.servers[2].host) -- beta.example.com
print(data.servers[1].port) -- 8080
```

`yaml.read(path)` does the same for a file.

Both functions return `nil` and an error message on failure. They don't raise
errors for bad input. The message gives the line number:

```lua
yaml.parse("a: 1\nb: [1, 2]\n")
--> nil, "line 2: flow collections are not supported"
```

### Encoding

```lua
local text = yaml.encode({
  name = "demo",
  enabled = true,
  version = "1.10",
  tags = { "lua", "yaml" },
  notes = "first line\nsecond line\n",
  servers = { { host = "alpha.example.com", port = 8080 } },
})
```

produces

```yaml
enabled: true
name: demo
notes: |
  first line
  second line
servers:
  - host: alpha.example.com
    port: 8080
tags:
  - lua
  - yaml
version: "1.10"
```

Keys come out in sorted order. A string is quoted only if it would otherwise
read back as something else. For example, `"1.10"` would become the number
`1.1`. `yaml.write(path, data)` writes the same text to a file.

Indentation defaults to 2 spaces. Pass `indent_width` to change it:

```lua
yaml.encode({ db = { host = "localhost" } }, { indent_width = 4 })
--> "db:\n    host: localhost\n"
```

### Editing a file in place

```lua
local ok, err = yaml.modify("config.yaml", function(data)
  data.version = data.version + 1
  return data
end)
```

`modify` reads the file, passes the table to your function, and writes back
whatever the function returns. It accepts the same options as `encode` as a
third argument.

### Dotted paths

```lua
yaml.get(data, "database.host")              -- nil if any part is missing
yaml.set(data, "database.host", "localhost") -- creates intermediate tables
```

## How YAML maps to Lua

| YAML                                                   | Lua                                                                    |
| ------------------------------------------------------ | ---------------------------------------------------------------------- |
| mapping                                                | table with string keys                                                 |
| sequence                                               | table with keys `1..n` and the metatable `{ __is_array = true }`       |
| `[]`, `{}`                                             | empty table; `[]` gets the `__is_array` metatable                      |
| `null`, `~`, or no value                               | `nil`; the key is absent, and null list items are dropped              |
| `true`, `false`, `yes`, `no`, `on`, `off`              | boolean (also accepted in `Title` and `UPPER` case)                    |
| integers, floats, `.inf`, `.nan`                       | number                                                                 |
| anything else                                          | string                                                                 |

When encoding, the encoder writes a table as a sequence if its keys are exactly
`1..n` or if it has the `__is_array` metatable. An empty Lua table could be
either a list or a map. The encoder writes it as `{}`, or as `[]` if it has
the `__is_array` metatable. Lists returned by `yaml.parse`
already have it. Inside Neovim, `vim.NIL` (for example from `vim.json.decode`)
is written as `null`. Functions, userdata, and threads raise an error.

Encoding and then parsing gives back the same data. The encoder also quotes
strings that YAML 1.1 parsers would read as another type, such as `y`,
`1_000`, or `2001-12-14`, so other YAML parsers read the output the same way.

## Supported YAML

The parser reads block-style YAML:

- mappings and sequences, including lists of mappings (`- key: value`) and
  nested lists (`- - item`)
- plain, single-quoted, and double-quoted strings, including escapes such as
  `\n`, `\t`, `\x41`, and `é`
- literal (`|`) and folded (`>`) multi-line strings, with the `-` and `+`
  chomping indicators and indentation indicators
- comments, and a single leading `---`

These return an error instead of a result:

- flow collections other than `[]` and `{}`
- anchors, aliases, and tags
- multiple documents
- plain or quoted strings that continue onto the next line
- duplicate keys and tab characters in indentation

## API

| Function                                   | Returns                                    |
| ------------------------------------------ | ------------------------------------------ |
| `yaml.parse(text)`                         | `table` or `nil, err`                      |
| `yaml.read(path)`                          | `table` or `nil, err`                      |
| `yaml.encode(value, options?)`             | `string` ending with a newline             |
| `yaml.write(path, value, options?)`        | `true` or `false, err`                     |
| `yaml.modify(path, fn, options?)`          | `true` or `false, err`                     |
| `yaml.get(data, dotted_path)`              | the value at the path, or `nil`            |
| `yaml.set(data, dotted_path, value)`       | `data`, after setting the value            |

`options` takes a single field, `indent_width`: a positive integer that
defaults to 2. Any other value raises an error.

## Testing

```sh
make test
```

The tests run in headless Neovim with
[plenary.nvim](https://github.com/nvim-lua/plenary.nvim). They clone plenary
into `/tmp/plenary.nvim` unless `PLENARY_DIR` points to an existing copy.

## Acknowledgements

This project started as a fork of
[jedi-knights/yaml.nvim](https://github.com/jedi-knights/yaml.nvim) by Omar
Crosby. It is now developed separately and does not follow changes in that
repository. Since the fork, the parser and encoder have been rewritten and
merged into a single file.

## License

MIT. The license text is at the top of [`lua/yaml.lua`](lua/yaml.lua), so it
stays with every copy of the file.
