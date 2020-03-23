local vim = vim

local luvjob = {}
luvjob.__index = luvjob

local function close_safely(handle)
  if not handle:is_closing() then
    handle:close()
  end
end

function luvjob:new(o)
  setmetatable(o, self)
  return o
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
  if self.on_exit then
    self:on_exit(code, signal)
  end

  if self.on_stdout then
    self.stdout:read_stop()
  end

  if self.on_stderr then
    self.stderr:read_stop()
  end

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

  print("Command:", options.command, "Args:", vim.inspect(options.args))
  self.handle, self.pid = vim.loop.spawn(options.command, options, vim.schedule_wrap(luvjob.shutdown_factory(self)))

  if self.on_stdout then
    self.stdout:read_start(vim.schedule_wrap(self.on_stdout))
  end

  if self.on_stderr then
    self.stderr:read_start(vim.schedule_wrap(self.on_stderr))
  end

  return self.handle, self.pid
end

function luvjob:wait()
  if self.handle == nil then
    vim.api.nvim_err_writeln(vim.inspect(self))
    return
  end

  while self.handle:is_active() or not self.is_shutdown do
    vim.cmd("sleep 10m")
  end
end

return luvjob
