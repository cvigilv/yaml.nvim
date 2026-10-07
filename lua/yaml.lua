-- yaml.nvim: parse and encode YAML from Lua.
-- This file is self-contained; it has no dependencies beyond the Lua standard library.

---@class YamlEncodeOptions
---@field indent_width? integer Number of spaces per indentation level (default: 2)

---@class Yaml
local M = {}

--------------------------------------------------------------------------------
-- Parser
--------------------------------------------------------------------------------

-- Helper function to trim whitespace
local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- Helper function to count leading spaces
local function count_indent(line)
  local spaces = line:match("^(%s*)")
  return #spaces
end

-- Helper function to parse a YAML value
local function parse_value(value)
  value = trim(value)

  -- Handle null/nil values
  if value == "null" or value == "~" or value == "" then
    return nil
  end

  -- Handle booleans
  if value == "true" or value == "yes" or value == "on" then
    return true
  end
  if value == "false" or value == "no" or value == "off" then
    return false
  end

  -- Handle numbers
  local num = tonumber(value)
  if num then
    return num
  end

  -- Handle quoted strings
  if value:match('^".*"$') or value:match("^'.*'$") then
    return value:sub(2, -2)
  end

  -- Return as string
  return value
end

-- Parse a YAML string into a Lua table
---@param content string The YAML content to parse
---@return table|nil parsed The parsed YAML as a Lua table, or nil on error
---@return string|nil error Error message if parsing failed
function M.parse(content)
  if not content or content == "" then
    return {}, nil
  end

  local lines = {}
  for line in content:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  local result = {}
  local stack = { { data = result, indent = -1 } }
  local i = 1

  while i <= #lines do
    local line = lines[i]
    local trimmed = trim(line)

    -- Skip empty lines and comments
    if trimmed == "" or trimmed:match("^#") then
      i = i + 1
      goto continue
    end

    local indent = count_indent(line)

    -- Pop stack until we find the right level
    while #stack > 1 and indent <= stack[#stack].indent do
      table.remove(stack)
    end

    local current = stack[#stack].data

    -- Handle list items
    if trimmed:match("^%- ") then
      local value_str = trimmed:sub(3)
      local value = parse_value(value_str)

      -- Ensure current is an array
      if not current[1] and next(current) == nil then
        -- Empty object, convert to array
        setmetatable(current, { __is_array = true })
      end

      if value_str:match(":") then
        -- List item with key-value
        local new_obj = {}
        table.insert(current, new_obj)
        local key, val = value_str:match("^([^:]+):%s*(.*)$")
        if key then
          key = trim(key)
          new_obj[key] = parse_value(val)
          table.insert(stack, { data = new_obj, indent = indent })
        end
      else
        table.insert(current, value)
      end
    -- Handle key-value pairs
    elseif trimmed:match(":") then
      local key, value = trimmed:match("^([^:]+):%s*(.*)$")
      if key then
        key = trim(key)
        value = trim(value or "")

        if value == "" or value == "|" or value == ">" then
          -- Multi-line string or nested object
          if value == "|" or value == ">" then
            -- Multi-line string
            local str_lines = {}
            i = i + 1
            while i <= #lines do
              local next_line = lines[i]
              local next_indent = count_indent(next_line)
              if next_indent <= indent then
                break
              end
              table.insert(str_lines, next_line:sub(indent + 3))
              i = i + 1
            end
            current[key] = table.concat(str_lines, "\n")
            i = i - 1
          else
            -- Check if next line is indented (nested structure)
            if i < #lines then
              local next_line = lines[i + 1]
              local next_indent = count_indent(next_line)
              if next_indent > indent then
                local next_trimmed = trim(next_line)
                if next_trimmed:match("^%- ") then
                  -- Next line is a list
                  current[key] = {}
                  setmetatable(current[key], { __is_array = true })
                else
                  -- Next line is an object
                  current[key] = {}
                end
                table.insert(stack, { data = current[key], indent = indent })
              else
                current[key] = nil
              end
            else
              current[key] = nil
            end
          end
        else
          current[key] = parse_value(value)
        end
      end
    end

    i = i + 1
    ::continue::
  end

  return result, nil
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

  return M.parse(content)
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

-- Helper function to check if a table is an array
local function is_array(t)
  if type(t) ~= "table" then
    return false
  end

  local mt = getmetatable(t)
  if mt and mt.__is_array then
    return true
  end

  local count = 0
  for k, _ in pairs(t) do
    count = count + 1
    if type(k) ~= "number" or k < 1 or k > count then
      return false
    end
  end
  return count > 0
end

-- Helper function to escape special characters in strings
local function escape_string(s)
  if type(s) ~= "string" then
    return tostring(s)
  end

  -- Check if string needs quotes
  if s:match("^%d+$") or s:match("^[%d%.]+$") or s:match("^[true|false|yes|no|on|off|null]$") or s:match("[:#%[%]{}]") or
    s:match("^%s") or s:match("%s$") or s:match("\n") then
    -- Use double quotes and escape special chars
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return '"' .. s .. '"'
  end

  return s
end

-- Convert a value to YAML string
---@param value any
---@param indent integer Current indentation, in spaces
---@param width integer Spaces added per nesting level
local function value_to_yaml(value, indent, width)
  local indent_str = string.rep(" ", indent)
  local step_str = string.rep(" ", width)

  if value == nil then
    return "null"
  elseif type(value) == "boolean" then
    return tostring(value)
  elseif type(value) == "number" then
    return tostring(value)
  elseif type(value) == "string" then
    -- Handle multi-line strings
    if value:match("\n") and not value:match("[:#%[%]{}]") then
      local lines = {}
      for line in value:gmatch("[^\n]+") do
        table.insert(lines, indent_str .. step_str .. line)
      end
      return "|\n" .. table.concat(lines, "\n")
    end
    return escape_string(value)
  elseif type(value) == "table" then
    if is_array(value) then
      -- Handle arrays
      if #value == 0 then
        return "[]"
      end

      local lines = {}
      for _, v in ipairs(value) do
        if type(v) == "table" and not is_array(v) then
          -- Complex object in array
          local obj_yaml = value_to_yaml(v, indent + width, width)
          if obj_yaml:match("\n") then
            table.insert(lines, indent_str .. "-")
            for line in obj_yaml:gmatch("[^\n]+") do
              table.insert(lines, indent_str .. step_str .. line)
            end
          else
            table.insert(lines, indent_str .. "- " .. obj_yaml)
          end
        else
          table.insert(lines, indent_str .. "- " .. value_to_yaml(v, indent + width, width))
        end
      end
      return "\n" .. table.concat(lines, "\n")
    else
      -- Handle objects
      local keys = {}
      for k in pairs(value) do
        table.insert(keys, k)
      end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)

      if #keys == 0 then
        return "{}"
      end

      local lines = {}
      for _, k in ipairs(keys) do
        local v = value[k]
        local key_str = escape_string(tostring(k))
        local val_yaml = value_to_yaml(v, indent + width, width)

        if type(v) == "table" then
          if val_yaml:match("^[\n]") then
            table.insert(lines, indent_str .. key_str .. ":" .. val_yaml)
          else
            table.insert(lines, indent_str .. key_str .. ": " .. val_yaml)
          end
        else
          table.insert(lines, indent_str .. key_str .. ": " .. val_yaml)
        end
      end
      return "\n" .. table.concat(lines, "\n")
    end
  end

  return "null"
end

-- Encode a Lua table into a YAML string
---@param data table The Lua table to encode
---@param options? YamlEncodeOptions Optional encoding options
---@return string yaml The YAML string
function M.encode(data, options)
  local width = get_indent_width(options)

  local yaml = value_to_yaml(data, 0, width)
  if type(data) == "table" and yaml:sub(1, 1) == "\n" then
    -- Remove leading newline
    yaml = yaml:sub(2)
  end

  return yaml
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
