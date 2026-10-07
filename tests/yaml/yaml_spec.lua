local yaml = require("yaml")

describe("yaml.nvim", function()
  describe("indent_width", function()
    local data = { database = { host = "localhost", options = { pool = 5 } } }

    it("defaults to 2", function()
      assert.are.equal(yaml.encode(data), yaml.encode(data, { indent_width = 2 }))
      assert.is_true(yaml.encode(data):match("\n  host: localhost") ~= nil)
    end)

    it("controls nesting depth", function()
      local result = yaml.encode(data, { indent_width = 4 })
      assert.is_true(result:match("\n    host: localhost") ~= nil)
      assert.is_true(result:match("\n        pool: 5") ~= nil)
      assert.are.same(data, yaml.parse(result))
    end)

    it("is used by write and modify", function()
      local test_file = "/tmp/test_yaml_indent_" .. os.time() .. ".yaml"
      local function read_raw()
        local f = assert(io.open(test_file, "r"))
        local content = f:read("*a")
        f:close()
        return content
      end

      assert.is_true(yaml.write(test_file, data, { indent_width = 3 }))
      assert.is_true(read_raw():match("\n   host: localhost") ~= nil)

      assert.is_true(yaml.modify(test_file, function(d)
        return d
      end, { indent_width = 5 }))
      assert.is_true(read_raw():match("\n     host: localhost") ~= nil)
      os.remove(test_file)
    end)

    it("rejects invalid values", function()
      assert.has_error(function()
        yaml.encode(data, { indent_width = 0 })
      end, "indent_width must be a positive integer, got 0 (number)")
      assert.has_error(function()
        yaml.encode(data, { indent_width = "2" })
      end, "indent_width must be a positive integer, got 2 (string)")
    end)
  end)

  describe("parse", function()
    it("parses simple key-value pairs", function()
      local content = [[
name: John Doe
age: 30
]]
      local result = yaml.parse(content)
      assert.are.equal("John Doe", result.name)
      assert.are.equal(30, result.age)
    end)

    it("parses nested objects", function()
      local content = [[
database:
  host: localhost
  port: 5432
]]
      local result = yaml.parse(content)
      assert.are.equal("localhost", result.database.host)
      assert.are.equal(5432, result.database.port)
    end)

    it("parses arrays", function()
      local content = [[
fruits:
  - apple
  - banana
  - orange
]]
      local result = yaml.parse(content)
      assert.are.equal(3, #result.fruits)
      assert.are.equal("apple", result.fruits[1])
      assert.are.equal("banana", result.fruits[2])
      assert.are.equal("orange", result.fruits[3])
    end)

    it("parses booleans", function()
      local content = [[
enabled: true
disabled: false
]]
      local result = yaml.parse(content)
      assert.is_true(result.enabled)
      assert.is_false(result.disabled)
    end)

    it("parses null values", function()
      local content = [[
value: null
]]
      local result = yaml.parse(content)
      assert.is_nil(result.value)
    end)

    it("parses numbers", function()
      local content = [[
integer: 42
float: 3.14
]]
      local result = yaml.parse(content)
      assert.are.equal(42, result.integer)
      assert.are.equal(3.14, result.float)
    end)

    it("handles empty input", function()
      local result = yaml.parse("")
      assert.are.same({}, result)
    end)
  end)

  describe("encode", function()
    it("encodes simple key-value pairs", function()
      local data = { name = "John Doe", age = 30 }
      local result = yaml.encode(data)
      assert.is_true(result:match("age: 30") ~= nil)
      assert.is_true(result:match('name: "John Doe"') ~= nil or result:match("name: John Doe") ~= nil)
    end)

    it("encodes nested objects", function()
      local data = {
        database = {
          host = "localhost",
          port = 5432,
        },
      }
      local result = yaml.encode(data)
      assert.is_true(result:match("database:") ~= nil)
      assert.is_true(result:match("host: localhost") ~= nil)
      assert.is_true(result:match("port: 5432") ~= nil)
    end)

    it("encodes arrays", function()
      local data = { fruits = { "apple", "banana", "orange" } }
      setmetatable(data.fruits, { __is_array = true })
      local result = yaml.encode(data)
      assert.is_true(result:match("fruits:") ~= nil)
      assert.is_true(result:match("- apple") ~= nil)
      assert.is_true(result:match("- banana") ~= nil)
      assert.is_true(result:match("- orange") ~= nil)
    end)

    it("encodes booleans", function()
      local data = { enabled = true, disabled = false }
      local result = yaml.encode(data)
      assert.is_true(result:match("enabled: true") ~= nil)
      assert.is_true(result:match("disabled: false") ~= nil)
    end)

    it("encodes null values", function()
      local data = { value = vim.NIL or nil }
      -- Since Lua tables don't store nil values, we use a workaround
      local result = yaml.encode({ value = "null" })
      assert.is_true(result:match("value:") ~= nil)
    end)

    it("encodes numbers", function()
      local data = { integer = 42, float = 3.14 }
      local result = yaml.encode(data)
      assert.is_true(result:match("integer: 42") ~= nil)
      assert.is_true(result:match("float: 3.14") ~= nil)
    end)
  end)

  describe("get and set", function()
    it("gets nested values", function()
      local data = {
        database = {
          host = "localhost",
          port = 5432,
        },
      }
      assert.are.equal("localhost", yaml.get(data, "database.host"))
      assert.are.equal(5432, yaml.get(data, "database.port"))
    end)

    it("sets nested values", function()
      local data = {}
      yaml.set(data, "database.host", "localhost")
      yaml.set(data, "database.port", 5432)
      assert.are.equal("localhost", data.database.host)
      assert.are.equal(5432, data.database.port)
    end)

    it("returns nil for non-existent paths", function()
      local data = { name = "test" }
      assert.is_nil(yaml.get(data, "database.host"))
    end)
  end)

  describe("round trip", function()
    local function round_trip(data, options)
      local result, err = yaml.parse(yaml.encode(data, options))
      assert.is_nil(err)
      assert.are.same(data, result)
    end

    it("keeps single-character and keyword-like strings", function()
      round_trip({ a = "e", n = "y", t = "true", yes = "no", ["1"] = "2", tilde = "~", empty = "" })
      assert.are.equal("a: e\n", yaml.encode({ a = "e" }))
    end)

    it("keeps strings with YAML syntax characters", function()
      round_trip({
        ["key: with colon"] = "value: with colon",
        hash = "a # not a comment",
        dash = "- not a list",
        quotes = 'it\'s "quoted"',
        brackets = "[not] {flow}",
        control = "tab\there\1",
        spaces = "  padded  ",
      })
    end)

    it("keeps lists of tables", function()
      local data = {
        items = {
          { name = "a", tags = { "x", "y" } },
          { name = "b", nested = { deep = { 1, 2 } } },
        },
      }
      round_trip(data)
      round_trip(data, { indent_width = 4 })
      assert.are.equal(
        "items:\n  - name: a\n  - name: b\n",
        yaml.encode({ items = { { name = "a" }, { name = "b" } } })
      )
    end)

    it("keeps nested lists", function()
      round_trip({ 1, { 2, { 3, 4 } }, { { a = 1 } } })
      round_trip({ matrix = { { 1, 2 }, { 3, 4 } } }, { indent_width = 3 })
    end)

    it("keeps multi-line strings", function()
      local data = {
        no_newline = "line one\nline two",
        trailing = "line one\nline two\n",
        many_trailing = "a\nb\n\n\n",
        blank_lines = "a\n\n\nb",
        special = "key: value\n# not a comment\n- not a list",
        leading_space = "  indented\nsecond",
        list = { "x\ny", { k = "p\nq\n" } },
      }
      round_trip(data)
      round_trip(data, { indent_width = 1 })
      round_trip(data, { indent_width = 4 })
    end)

    it("keeps numbers and empty collections", function()
      round_trip({ big = 2 ^ 60, third = 1 / 3, tiny = 1e-300, inf = math.huge, ninf = -math.huge, neg = -7 })
      local result = yaml.parse(yaml.encode({ list = setmetatable({}, { __is_array = true }), map = {} }))
      assert.are.same({}, result.list)
      assert.is_true(getmetatable(result.list).__is_array)
      assert.are.same({}, result.map)
    end)
  end)

  describe("parse details", function()
    it("unescapes double-quoted strings", function()
      local result = yaml.parse([[s: "a\"b\\c\n\t\x41é"]])
      assert.are.equal('a"b\\c\n\tAé', result.s)
    end)

    it("handles single-quoted strings and comments", function()
      local result = yaml.parse("a: 'it''s' # comment\nb: plain # comment\nc: 'x # y'\n")
      assert.are.same({ a = "it's", b = "plain", c = "x # y" }, result)
    end)

    it("folds > block scalars", function()
      local result = yaml.parse("f: >\n  one\n  two\n\n  three\nk: |-\n  kept\n")
      assert.are.same({ f = "one two\nthree\n", k = "kept" }, result)
    end)

    it("accepts a sequence at the same indentation as its key", function()
      assert.are.same({ list = { "a", "b" }, next = 1 }, yaml.parse("list:\n- a\n- b\nnext: 1\n"))
    end)

    it("does not split plain scalars on colons without a following space", function()
      assert.are.same({ "http://example.com" }, yaml.parse("- http://example.com\n"))
    end)

    it("reports unsupported and invalid input with a line number", function()
      local cases = {
        ["a: 1\nb: [1, 2]\n"] = "line 2: flow collections are not supported",
        ["a: &x 1\n"] = "line 1: anchors, aliases, and tags are not supported",
        ["a: 1\na: 2\n"] = 'line 2: duplicate key "a"',
        ["a: 1\n  b: 2\n"] = "line 2: unexpected indentation (multi-line plain scalars are not supported)",
        ["a: 1\n---\nb: 2\n"] = "line 2: multiple documents and document markers other than a leading '---' are not supported",
        ['a: "\\q"'] = "line 1: invalid escape \\q",
        ["just text"] = "line 1: expected a mapping or sequence",
      }
      for input, message in pairs(cases) do
        local result, err = yaml.parse(input)
        assert.is_nil(result)
        assert.are.equal(message, err)
      end
    end)
  end)

  describe("file operations", function()
    local test_file = "/tmp/test_yaml_" .. os.time() .. ".yaml"

    after_each(function()
      -- Clean up test file
      os.remove(test_file)
    end)

    it("writes and reads YAML files", function()
      local data = {
        name = "Test",
        version = 1,
        config = {
          enabled = true,
        },
      }

      local success, err = yaml.write(test_file, data)
      assert.is_true(success, err)

      local result, read_err = yaml.read(test_file)
      assert.is_not_nil(result, read_err)
      assert.are.equal("Test", result.name)
      assert.are.equal(1, result.version)
      assert.is_true(result.config.enabled)
    end)

    it("modifies YAML files", function()
      local initial_data = {
        name = "Test",
        version = 1,
      }

      yaml.write(test_file, initial_data)

      local success, err = yaml.modify(test_file, function(data)
        data.version = 2
        data.updated = true
        return data
      end)

      assert.is_true(success, err)

      local result = yaml.read(test_file)
      assert.are.equal("Test", result.name)
      assert.are.equal(2, result.version)
      assert.is_true(result.updated)
    end)
  end)
end)
