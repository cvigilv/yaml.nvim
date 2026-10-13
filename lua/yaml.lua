-- yaml.lua: parse and encode YAML from Lua.
-- https://github.com/cvigilv/yaml.nvim
--
-- This file is self-contained; it needs only the Lua standard library. Copy it
-- into a project and load it with require. Inside Neovim, vim.NIL is encoded
-- as null.
--
-- MIT License
--
-- Copyright (c) 2025 Omar Crosby
-- Copyright (c) 2026 Carlos Vigil-Vásquez
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

---@class YamlEncodeOptions
---@field indent_width? integer Number of spaces per indentation level (default: 2)

---@class Yaml
local M = {}

-- Sentinel for null values in Neovim (e.g. from vim.json.decode)
local NIL = rawget(_G, "vim") and vim.NIL

--------------------------------------------------------------------------------
-- Scalars
--------------------------------------------------------------------------------

local NULL_WORDS = { ["~"] = true, null = true, Null = true, NULL = true }

local BOOL_WORDS = {
  ["true"] = true,
  True = true,
  TRUE = true,
  yes = true,
  Yes = true,
  YES = true,
  on = true,
  On = true,
  ON = true,
  ["false"] = false,
  False = false,
  FALSE = false,
  no = false,
  No = false,
  NO = false,
  off = false,
  Off = false,
  OFF = false,
}

local SPECIAL_NUMBERS = {}
for _, inf in ipairs({ ".inf", ".Inf", ".INF" }) do
  SPECIAL_NUMBERS[inf] = math.huge
  SPECIAL_NUMBERS["+" .. inf] = math.huge
  SPECIAL_NUMBERS["-" .. inf] = -math.huge
end
for _, nan in ipairs({ ".nan", ".NaN", ".NAN" }) do
  SPECIAL_NUMBERS[nan] = 0 / 0
end

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Convert the text of a plain (unquoted) scalar to a Lua value. The encoder
-- quotes every string for which this does not return the string itself.
local function plain_value(s)
  if s == "" or NULL_WORDS[s] then
    return nil
  end
  local bool = BOOL_WORDS[s]
  if bool ~= nil then
    return bool
  end
  local special = SPECIAL_NUMBERS[s]
  if special then
    return special
  end
  -- The digit requirement keeps tonumber from accepting "inf" and "nan"
  if s:find("^[-+]?%.?%d") then
    local num = tonumber(s)
    if type(num) == "number" then
      return num
    end
  end
  return s
end

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

-- Marks errors caused by invalid input, as opposed to bugs in the parser
local ParseError = {}

-- Parser state: `lines` of the document, `pos` of the next unread line, and
-- `current`, the line that error messages refer to
---@class YamlParserState
---@field lines string[]
---@field pos integer
---@field current integer

local function fail(p, msg)
  error(setmetatable({ message = ("line %d: %s"):format(p.current, msg) }, ParseError), 0)
end

local function indent_of(line)
  return #line:match("^ *")
end

local function is_blank_or_comment(line)
  return line:find("^%s*$") ~= nil or line:find("^%s*#") ~= nil
end

local function is_sequence_entry(text)
  return text == "-" or text:find("^%-%s") ~= nil
end

-- Skip blank and comment lines; return the next line and its indentation
local function peek(p)
  local lines = p.lines
  while p.pos <= #lines and is_blank_or_comment(lines[p.pos]) do
    p.pos = p.pos + 1
  end
  local line = lines[p.pos]
  if not line then
    return nil
  end
  local indent = indent_of(line)
  if line:sub(indent + 1, indent + 1) == "\t" then
    p.current = p.pos
    fail(p, "tabs are not allowed in indentation")
  end
  return line, indent
end

-- Index of the quote that closes the quoted scalar starting at text[1], or nil
local function closing_quote(text)
  local q = text:sub(1, 1)
  local i = 2
  while i <= #text do
    local c = text:sub(i, i)
    if q == '"' and c == "\\" then
      i = i + 2
    elseif c == q then
      if q == "'" and text:sub(i + 1, i + 1) == "'" then
        i = i + 2
      else
        return i
      end
    else
      i = i + 1
    end
  end
  return nil
end

local function utf8_char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

local ESCAPES = {
  ["\\"] = "\\",
  ['"'] = '"',
  ["/"] = "/",
  [" "] = " ",
  ["0"] = "\0",
  a = "\a",
  b = "\b",
  e = "\27",
  f = "\f",
  n = "\n",
  r = "\r",
  t = "\t",
  v = "\v",
}

local function unescape_double(p, s)
  local out, i = {}, 1
  while true do
    local j = s:find("\\", i, true)
    if not j then
      out[#out + 1] = s:sub(i)
      break
    end
    out[#out + 1] = s:sub(i, j - 1)
    local c = s:sub(j + 1, j + 1)
    local hex_len = (c == "x" and 2) or (c == "u" and 4) or (c == "U" and 8)
    if hex_len then
      local hex = s:sub(j + 2, j + 1 + hex_len)
      if #hex ~= hex_len or hex:find("%X") then
        fail(p, "invalid escape \\" .. c .. hex)
      end
      local cp = tonumber(hex, 16)
      if cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
        fail(p, "unsupported code point in escape \\" .. c .. hex)
      end
      out[#out + 1] = utf8_char(cp)
      i = j + 2 + hex_len
    else
      local e = ESCAPES[c]
      if not e then
        fail(p, "invalid escape \\" .. c)
      end
      out[#out + 1] = e
      i = j + 2
    end
  end
  return table.concat(out)
end

-- Parse a quoted scalar at the start of `text`; return its value and the text after it
local function parse_quoted(p, text)
  local close = closing_quote(text)
  if not close then
    fail(p, "unterminated quoted string (multi-line quoted strings are not supported)")
  end
  local inner = text:sub(2, close - 1)
  if text:sub(1, 1) == '"' then
    return unescape_double(p, inner), text:sub(close + 1)
  end
  return (inner:gsub("''", "'")), text:sub(close + 1)
end

-- Split a mapping entry into its key and the text after the colon; nil if
-- `text` is not a mapping entry
local function split_key(p, text)
  local c = text:sub(1, 1)
  if c == '"' or c == "'" then
    local close = closing_quote(text)
    if not close then
      return nil
    end
    local after = text:sub(close + 1)
    local rest = after:match("^%s*:%s+(.*)$") or (after:find("^%s*:$") and "")
    if not rest then
      return nil
    end
    return (parse_quoted(p, text)), rest
  end
  local colon = text:find(":%s") or (text:sub(-1) == ":" and #text)
  local comment = text:find("%s#")
  if not colon or (comment and comment < colon) then
    return nil
  end
  local key = trim(text:sub(1, colon - 1))
  if key == "" then
    return nil
  end
  return key, text:sub(colon + 1)
end

-- Parse a scalar written on the same line as its key or sequence marker
local function parse_scalar(p, text)
  local c = text:sub(1, 1)
  if c == '"' or c == "'" then
    local value, after = parse_quoted(p, text)
    if not (after:find("^%s*$") or after:find("^%s+#")) then
      fail(p, "unexpected text after quoted string")
    end
    return value
  end

  local comment = text:find("%s#")
  if comment then
    text = trim(text:sub(1, comment - 1))
  end
  if text:find("^%[%s*%]$") then
    return setmetatable({}, { __is_array = true })
  end
  if text:find("^{%s*}$") then
    return {}
  end
  if text:find("^[%[{]") then
    fail(p, "flow collections are not supported")
  end
  if text:find("^[&*!]") then
    fail(p, "anchors, aliases, and tags are not supported")
  end
  if text:find("^[%%@`]") or text:find("^[-?:]%s") or text:find("^[-?:]$") then
    fail(p, "invalid plain scalar " .. text)
  end
  return plain_value(text)
end

-- Join the lines of a folded block scalar
local function fold_lines(body, last)
  local out, prev, empties = {}, nil, 0
  for i = 1, last do
    local line = body[i]
    if line == "" then
      empties = empties + 1
    else
      local kind = line:find("^%s") and "more_indented" or "text"
      if prev == "text" and kind == "text" then
        out[#out + 1] = empties == 0 and " " or string.rep("\n", empties)
      elseif prev then
        -- Line breaks next to more-indented lines are kept
        out[#out + 1] = string.rep("\n", empties + 1)
      else
        out[#out + 1] = string.rep("\n", empties)
      end
      out[#out + 1] = line
      prev, empties = kind, 0
    end
  end
  return table.concat(out)
end

-- Parse a literal (|) or folded (>) block scalar whose header is `header`;
-- `p.pos` is the line after the header
local function parse_block_scalar(p, header, parent_indent)
  local style = header:sub(1, 1)
  local indicators, trailing = header:match("^.([%+%-%d]*)(.*)$")
  local chomp = indicators:match("[%+%-]")
  local digit = indicators:match("[1-9]")
  if
    #indicators ~= (chomp and 1 or 0) + (digit and 1 or 0) or not (trailing:find("^%s*$") or trailing:find("^%s+#"))
  then
    fail(p, "invalid block scalar header " .. header)
  end

  local lines = p.lines
  local content_indent
  if digit then
    content_indent = parent_indent + tonumber(digit)
  else
    -- The first non-blank line sets the indentation
    for i = p.pos, #lines do
      if lines[i]:find("%S") then
        content_indent = indent_of(lines[i])
        break
      end
    end
    if not content_indent or content_indent <= parent_indent then
      content_indent = parent_indent + 1
    end
  end

  local body = {}
  while p.pos <= #lines do
    local line = lines[p.pos]
    if line:find("%S") and indent_of(line) < content_indent then
      break
    end
    body[#body + 1] = line:sub(content_indent + 1)
    p.pos = p.pos + 1
  end

  local last = #body
  while last > 0 and body[last] == "" do
    last = last - 1
  end
  local trailing_empty = #body - last
  if last == 0 then
    return chomp == "+" and string.rep("\n", trailing_empty) or ""
  end

  local text = style == "|" and table.concat(body, "\n", 1, last) or fold_lines(body, last)
  if chomp == "-" then
    return text
  elseif chomp == "+" then
    return text .. string.rep("\n", trailing_empty + 1)
  end
  return text .. "\n"
end

local parse_node, parse_mapping, parse_sequence

-- Parse the value that follows a mapping key or sequence marker on the same line;
-- an empty `rest` means the value is a nested block (or null)
local function parse_value(p, rest, parent_indent, allow_same_indent_sequence)
  rest = trim(rest)
  if rest == "" or rest:find("^#") then
    local line, indent = peek(p)
    if line then
      if indent > parent_indent then
        return parse_node(p, indent)
      end
      -- A mapping value may be a sequence at the key's own indentation
      if allow_same_indent_sequence and indent == parent_indent and is_sequence_entry(line:sub(indent + 1)) then
        return parse_sequence(p, indent)
      end
    end
    return nil
  end
  local c = rest:sub(1, 1)
  if c == "|" or c == ">" then
    return parse_block_scalar(p, rest, parent_indent)
  end
  return parse_scalar(p, rest)
end

function parse_mapping(p, indent)
  local map, seen = {}, {}
  while true do
    local line, line_indent = peek(p)
    if not line or line_indent < indent then
      break
    end
    p.current = p.pos
    if line_indent > indent then
      fail(p, "unexpected indentation (multi-line plain scalars are not supported)")
    end
    local text = line:sub(indent + 1)
    if is_sequence_entry(text) then
      fail(p, "expected 'key: value', found a sequence entry")
    end
    local key, rest = split_key(p, text)
    if not key then
      fail(p, "expected 'key: value'")
    end
    if seen[key] then
      fail(p, ("duplicate key %q"):format(key))
    end
    seen[key] = true
    p.pos = p.pos + 1
    map[key] = parse_value(p, rest, indent, true)
  end
  return map
end

function parse_sequence(p, indent)
  local seq = setmetatable({}, { __is_array = true })
  while true do
    local line, line_indent = peek(p)
    if not line or line_indent < indent then
      break
    end
    p.current = p.pos
    if line_indent > indent then
      fail(p, "unexpected indentation (multi-line plain scalars are not supported)")
    end
    local text = line:sub(indent + 1)
    if not is_sequence_entry(text) then
      break
    end
    local item = text:sub(3)
    local column = indent + 2 + #item:match("^%s*")
    item = trim(item)
    if is_sequence_entry(item) or (not item:find("^#") and split_key(p, item)) then
      -- Compact nested collection ("- key: value" or "- - item"): reparse the
      -- rest of the line as a block that starts at `column`
      p.lines[p.pos] = string.rep(" ", column) .. item
      seq[#seq + 1] = parse_node(p, column)
    else
      p.pos = p.pos + 1
      seq[#seq + 1] = parse_value(p, item, indent, false)
    end
  end
  return seq
end

-- Parse the mapping or sequence whose first line is at `p.pos`
function parse_node(p, indent)
  p.current = p.pos
  local text = p.lines[p.pos]:sub(indent + 1)
  if is_sequence_entry(text) then
    return parse_sequence(p, indent)
  elseif split_key(p, text) then
    return parse_mapping(p, indent)
  end
  fail(p, "expected 'key: value' or '- item'")
end

local function parse_document(content)
  content = content:gsub("^\239\187\191", ""):gsub("\r\n?", "\n")
  if content:sub(-1) ~= "\n" then
    content = content .. "\n"
  end
  local lines = {}
  for line in content:gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  local p = { lines = lines, pos = 1, current = 1 }

  -- A single leading "---" is allowed; other document markers are not
  local seen_content = false
  for i, line in ipairs(lines) do
    p.current = i
    if line:find("^%%") then
      fail(p, "directives are not supported")
    end
    local marker = line:match("^%-%-%-") or line:match("^%.%.%.")
    if marker and (#line == 3 or line:find("^...%s")) then
      if marker ~= "---" or seen_content or not is_blank_or_comment(line:sub(4)) then
        fail(p, "multiple documents and document markers other than a leading '---' are not supported")
      end
      lines[i] = ""
      seen_content = true
    elseif not is_blank_or_comment(line) then
      seen_content = true
    end
  end

  local line, indent = peek(p)
  if not line then
    return {}
  end
  local root
  local text = line:sub(indent + 1)
  if is_sequence_entry(text) or split_key(p, text) then
    root = parse_node(p, indent)
  else
    -- The only scalar documents accepted are the empty collections [] and {}
    p.current = p.pos
    root = parse_scalar(p, text)
    if type(root) ~= "table" then
      fail(p, "expected a mapping or sequence")
    end
    p.pos = p.pos + 1
  end
  if peek(p) then
    p.current = p.pos
    fail(p, "unexpected content (check indentation)")
  end
  return root
end

-- Parse a YAML string into a Lua table
---@param content string The YAML content to parse
---@return table|nil parsed The parsed YAML as a Lua table, or nil on error
---@return string|nil error Error message if parsing failed
function M.parse(content)
  if content == nil or content == "" then
    return {}, nil
  end
  if type(content) ~= "string" then
    error("content must be a string, got " .. type(content), 2)
  end

  local ok, result = pcall(parse_document, content)
  if ok then
    return result, nil
  end
  if getmetatable(result) == ParseError then
    return nil, result.message
  end
  error(result, 0)
end

-- Parse a YAML file into a Lua table
---@param filepath string Path to the YAML file
---@return table|nil parsed The parsed YAML as a Lua table, or nil on error
---@return string|nil error Error message if parsing failed
function M.read(filepath)
  local file, err = io.open(filepath, "r")
  if not file then
    return nil, "Failed to open file: " .. (err or "unknown error")
  end

  local content = file:read("*a")
  file:close()

  local data, parse_err = M.parse(content)
  if not data then
    return nil, filepath .. ": " .. parse_err
  end
  return data, nil
end

--------------------------------------------------------------------------------
-- Encoder
--------------------------------------------------------------------------------

-- Validate encoding options and return the indentation width
---@param options? YamlEncodeOptions
---@return integer
local function get_indent_width(options)
  local width = options and options.indent_width
  if width == nil then
    return 2
  end
  if type(width) ~= "number" or width < 1 or width % 1 ~= 0 then
    error(("indent_width must be a positive integer, got %s (%s)"):format(tostring(width), type(width)), 3)
  end
  return width
end

-- A table is encoded as a sequence if it is marked with the __is_array
-- metatable field or its keys are exactly 1..n
local function is_array(t)
  local mt = getmetatable(t)
  if mt and mt.__is_array then
    return true
  end

  local count, max = 0, 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    count = count + 1
    max = math.max(max, k)
  end
  return count > 0 and count == max
end

-- Non-empty tables are written in block style; empty ones as [] or {}
local function is_collection(value)
  if type(value) ~= "table" then
    return false
  end
  if is_array(value) then
    return value[1] ~= nil
  end
  return next(value) ~= nil
end

local function format_number(n)
  if n ~= n then
    return ".nan"
  elseif n == math.huge then
    return ".inf"
  elseif n == -math.huge then
    return "-.inf"
  elseif n % 1 == 0 and math.abs(n) < 2 ^ 53 then
    return ("%d"):format(n)
  end
  -- Use the shortest of these that reads back as the same number
  local s = ("%.14g"):format(n)
  if tonumber(s) ~= n then
    s = ("%.17g"):format(n)
  end
  -- YAML 1.1 floats require a decimal point: 1e+20 is a string, 1.0e+20 a number
  if not s:find("%.") then
    s = s:gsub("e", ".0e", 1)
  end
  return s
end

-- Plain scalars that YAML 1.1 parsers read as non-strings, beyond plain_value's rules
local YAML11_WORDS = { y = true, Y = true, n = true, N = true, ["<<"] = true, ["="] = true }

-- Whether a string must be quoted to be read back as the same string, by this
-- parser and by YAML 1.1 parsers
local function needs_quotes(s)
  return s == ""
    or s:find("^%s") ~= nil
    or s:find("%s$") ~= nil
    or s:find("%c") ~= nil
    or s:find("^[%-?:,%[%]{}#&*!|>'\"%%@`]") ~= nil
    or s:find(":%s") ~= nil
    or s:find(":$") ~= nil
    or s:find("%s#") ~= nil
    -- Numbers, dates, and sexagesimal values such as 1:20 in YAML 1.1
    or s:find("^[+.]?%d") ~= nil
    or YAML11_WORDS[s] ~= nil
    or plain_value(s) ~= s
end

local QUOTE_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return QUOTE_ESCAPES[c] or ("\\x%02X"):format(c:byte())
  end) .. '"'
end

local function encode_string(s)
  return needs_quotes(s) and quote(s) or s
end

local function encode_scalar(value)
  local t = type(value)
  if value == nil or (NIL and value == NIL) then
    return "null"
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "number" then
    return format_number(value)
  elseif t == "string" then
    return encode_string(value)
  elseif t == "table" then
    return is_array(value) and "[]" or "{}"
  end
  error("cannot encode a value of type " .. t)
end

local function encode_key(k)
  local t = type(k)
  if t == "string" then
    return encode_string(k)
  elseif t == "number" then
    return encode_string(format_number(k))
  elseif t == "boolean" then
    return encode_string(tostring(k))
  end
  error("cannot encode a table key of type " .. t)
end

-- Header and content lines for writing a multi-line string as a literal
-- block scalar, or nil if the string must be quoted instead
local function block_literal(s)
  if not s:find("\n") then
    return nil
  end
  local body, newlines = s:match("^(.-)(\n*)$")
  if body == "" or (body:gsub("[\n\t]", "")):find("%c") then
    return nil
  end
  -- Leading whitespace on the first line would need an indentation indicator
  if body:match("^\n*(.)"):find("%s") then
    return nil
  end
  local lines = {}
  for line in (body .. "\n"):gmatch("(.-)\n") do
    -- Whitespace-only lines would be read back as empty lines
    if line:find("^%s+$") then
      return nil
    end
    lines[#lines + 1] = line
  end
  for _ = 2, #newlines do
    lines[#lines + 1] = ""
  end
  local header = (#newlines == 0 and "|-") or (#newlines == 1 and "|") or "|+"
  return header, lines
end

-- Append "<prefix> <value>" for a value that is not a non-empty table
local function encode_inline(prefix, value, indent, width, out)
  local sep = prefix == "" and "" or " "
  if type(value) == "string" then
    local header, lines = block_literal(value)
    if header then
      out[#out + 1] = prefix .. sep .. header
      local pad = string.rep(" ", indent + width)
      for _, line in ipairs(lines) do
        out[#out + 1] = line == "" and "" or pad .. line
      end
      return
    end
  end
  out[#out + 1] = prefix .. sep .. encode_scalar(value)
end

-- Append the lines of a non-empty table, indented by `indent` spaces
local function encode_block(value, indent, width, out)
  local pad = string.rep(" ", indent)
  if is_array(value) then
    -- Item content starts after "- ", so it is indented at least 2
    local offset = math.max(width, 2)
    for _, item in ipairs(value) do
      if is_collection(item) then
        -- Compact form: the item's first line shares the line with its "-"
        local first = #out + 1
        encode_block(item, indent + offset, width, out)
        out[first] = pad .. "-" .. string.rep(" ", offset - 1) .. out[first]:sub(indent + offset + 1)
      else
        encode_inline(pad .. "-", item, indent, width, out)
      end
    end
  else
    local keys = {}
    for k in pairs(value) do
      table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)

    for _, k in ipairs(keys) do
      local v = value[k]
      local prefix = pad .. encode_key(k) .. ":"
      if is_collection(v) then
        out[#out + 1] = prefix
        encode_block(v, indent + width, width, out)
      else
        encode_inline(prefix, v, indent, width, out)
      end
    end
  end
end

-- Encode a Lua value into a YAML string
---@param data any The Lua value to encode
---@param options? YamlEncodeOptions Optional encoding options
---@return string yaml The YAML string, ending with a newline
function M.encode(data, options)
  local width = get_indent_width(options)

  local out = {}
  if is_collection(data) then
    encode_block(data, 0, width, out)
  else
    encode_inline("", data, 0, width, out)
  end
  return table.concat(out, "\n") .. "\n"
end

-- Write a Lua table to a YAML file
---@param filepath string Path to the output file
---@param data table The Lua table to encode
---@param options? YamlEncodeOptions Optional encoding options
---@return boolean success
---@return string|nil error Error message if writing failed
function M.write(filepath, data, options)
  local yaml = M.encode(data, options)

  local file, err = io.open(filepath, "w")
  if not file then
    return false, "Failed to open file for writing: " .. (err or "unknown error")
  end

  file:write(yaml)
  file:close()

  return true, nil
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Load, modify, and save a YAML file
---@param filepath string Path to the YAML file
---@param modifier function Function that takes and returns a table
---@param options? YamlEncodeOptions Optional encoding options used when saving
---@return boolean success
---@return string|nil error Error message if operation failed
function M.modify(filepath, modifier, options)
  local data, err = M.read(filepath)
  if not data then
    return false, err
  end

  local modified = modifier(data)
  if not modified then
    return false, "Modifier function returned nil"
  end

  return M.write(filepath, modified, options)
end

-- Helper function to safely access nested values
---@param data table The table to query
---@param path string Dot-separated path (e.g., "database.host")
---@return any value The value at the path, or nil if not found
function M.get(data, path)
  local keys = {}
  for key in path:gmatch("[^%.]+") do
    table.insert(keys, key)
  end

  local current = data
  for _, key in ipairs(keys) do
    if type(current) ~= "table" then
      return nil
    end
    current = current[key]
  end

  return current
end

-- Helper function to safely set nested values
---@param data table The table to modify
---@param path string Dot-separated path (e.g., "database.host")
---@param value any The value to set
---@return table data The modified table
function M.set(data, path, value)
  local keys = {}
  for key in path:gmatch("[^%.]+") do
    table.insert(keys, key)
  end

  local current = data
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(current[key]) ~= "table" then
      current[key] = {}
    end
    current = current[key]
  end

  current[keys[#keys]] = value
  return data
end

return M
