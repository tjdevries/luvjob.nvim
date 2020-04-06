# luvjob.nvim

LibUV Jobs for Nvim in Lua.

The object of the plugin is to provide a compatible interface to `jobstart` and associated `job*` commands defined in Neovim in Lua, without having to move back and forth between Lua & VimL.


## Example

(More details to be added later)

An example of a plugin that uses it is: github.com/tjdevries/apyrori.nvim

```lua

-- Config not shown.
local config = {}

local on_read = function(err, data)
    if err then
      vim.api.nvim_err_writeln("APYRORI ERROR: " .. vim.inspect(err))
      return
    end

    if data == nil then
      return
    end

    for _, line in ipairs(vim.fn.split(data, "\n")) do
      table.insert(results, line)
    end
end

local grepper = luvjob:new({
    command = config.command,
    args = config.args(text),
    cwd = directory,
    on_stdout = on_read,
    on_stderr = on_read,
    on_exit = function(...)
      config.parser(results, counts)
    end,
})

grepper:start()
grepper:wait()

```


## Acknowledgements

Shoutout to https://github.com/TravonteD/luajob/ for giving me the idea and some of the outline of the code, but I ended up going slightly different routes than that.
