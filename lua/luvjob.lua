local vim = vim

local luvjob = {}
luvjob.__index = luvjob

local function close_safely(handle)
  if not handle:is_closing() then
    handle:close()
  end
end

function luvjob:new(o)
  local obj = {}

  obj.command = o.command
  obj.args = o.args
  obj.cwd = o.cwd
  obj.env = o.env
  obj.detach = o.detach

  obj._user_on_stdout = o.on_stdout
  obj._user_on_stderr = o.on_stderr
  obj._user_on_exit = o.on_exit

  -- Could expose these I suppose
  obj._raw_stdout = ''
  obj._raw_stderr = ''

  obj._raw_output = ''

  return setmetatable(obj, self)
end

function luvjob:send(data)
  self.stdin:write(data)
  self.stdin:shutdown()
end

function luvjob:stop()
  close_safely(self.stdin)
  close_safely(self.stderr)
  close_safely(self.stdout)
  close_safely(self.handle)
end

--- Factory to correctly bind the shutdown function when passing to libuv
function luvjob.shutdown_factory(child)
  return function(code, signal)
    child:shutdown(code, signal)
  end
end

function luvjob:shutdown(code, signal)
  self.code = code
  self.signal = signal

  if self._user_on_exit then
    self:_user_on_exit(code, signal)
  end

  self.stdout:read_stop()
  self.stderr:read_stop()

  self:stop()

  self.is_shutdown = true
end

function luvjob:create_options()
  local options = {}

  self.stdin = vim.loop.new_pipe(false)
  self.stdout = vim.loop.new_pipe(false)
  self.stderr = vim.loop.new_pipe(false)

  options.command = self.command
  options.args = self.args
  options.stdio = {
    self.stdin,
    self.stdout,
    self.stderr
  }

  if self.cwd then
    options.cwd = self.cwd
  end

  if self.env then
    options.env = self.env
  end

  if self.detach then
    options.detach = self.detach
  end

  return options
end

function luvjob:start()
  local options = self:create_options()

  self.handle, self.pid = vim.loop.spawn(
    options.command,
    options,
    vim.schedule_wrap(luvjob.shutdown_factory(self))
  )

  self.stdout:read_start(vim.schedule_wrap(function(err, data)
    if data ~= nil then
      local subbed = data:gsub("\r", "")
      self._raw_stdout  = self._raw_stdout .. subbed
      self._raw_output  = self._raw_output .. subbed
    end

    if self._user_on_stdout then
      self._user_on_stdout(err, data)
    end
  end))

  self.stderr:read_start(vim.schedule_wrap(function(err, data)
    if data ~= nil then
      local subbed = data:gsub("\r", "")
      self._raw_stderr  = self._raw_stderr .. subbed
      self._raw_output  = self._raw_output .. subbed
    end

    if self._user_on_stderr then
      self._user_on_stderr(err, data)
    end
  end))

  return self
end

function luvjob:stdout_result()
  return vim.split(self._raw_stdout, "\n")
end

function luvjob:stderr_result()
  return vim.split(self._raw_stderr, "\n")
end

function luvjob:result()
  local res = vim.split(self._raw_output, "\n")

  if res[#res] == '' then
    table.remove(res, #res)
  end

  return res
end

function luvjob:pid()
  return self.pid
end

function luvjob:wait()
  if self.handle == nil then
    vim.api.nvim_err_writeln(vim.inspect(self))
    return
  end

  while not vim.wait(100, function() return not self.handle:is_active() or self.is_shutdown end, 10) do
  end

  return self
end

function luvjob:co_wait(wait_time)
  wait_time = wait_time or 5

  if self.handle == nil then
    vim.api.nvim_err_writeln(vim.inspect(self))
    return
  end

  while not vim.wait(wait_time, function() return self.is_shutdown end) do
    coroutine.yield()
  end

  return self
end


function luvjob.accumulate_results(results)
  return function(err, data)
    if data == nil then
      if results[#results] == '' then
        table.remove(results, #results)
      end

      return
    end

    if results[1] == nil then
      results[1] = ''
    end

    -- Get rid of pesky \r
    data = data:gsub("\r", "")

    local line, start, found_newline
    while true do
      start = string.find(data, "\n") or #data
      found_newline = string.find(data, "\n")

      line = string.sub(data, 1, start)
      data = string.sub(data, start + 1, -1)

      line = line:gsub("\r", "")
      line = line:gsub("\n", "")

      results[#results] = (results[#results] or '') .. line

      if found_newline then
        table.insert(results, '')
      else
        break
      end
    end

    -- if found_newline and results[#results] == '' then
    --   table.remove(results, #results)
    -- end

    -- if string.find(data, "\n") then
    --   for _, line in ipairs(vim.fn.split(data, "\n")) do
    --     line = line:gsub("\n", "")
    --     line = line:gsub("\r", "")

    --     table.insert(results, line)
    --   end
    -- else
    --   results[#results] = results[#results] .. data
    -- end
  end
end

--- Wait for all jobs to complete
function luvjob.join(...)
  local jobs_to_wait = {...}

  while true do
    if #jobs_to_wait == 0 then
      break
    end

    local current_job = jobs_to_wait[1]
    if current_job.is_shutdown then
      table.remove(jobs_to_wait, 1)
    end

    -- vim.cmd.sleep(10)
    vim.cmd("sleep 100m")
  end
end

return luvjob
