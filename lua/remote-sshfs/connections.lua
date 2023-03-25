local utils = require "remote-sshfs.utils"
local handler = require "remote-sshfs.handler"

local hosts = {}
local config = {}
local sshfs_job_id = nil

local M = {}

M.setup = function(opts)
  config = opts
  utils.setup_sshfs(config)
  hosts = utils.parse_hosts_from_configs(config)
end

M.list_hosts = function()
  return hosts
end

M.connect = function(host)
  -- Initialize host variables
  local remote_host = host["HostName"]
  if config.ui.confirm.connect then
    local prompt = "Connect to remote host (" .. remote_host .. ")?"
    utils.prompt_yes_no(prompt, function(item_short)
      utils.clear_prompt()
      if item_short == "y" then
        M.init_host(host)
      end
    end)
  else
    M.init_host(host)
  end
end

M.init_host = function(host)
  -- Create/confirm mount directory
  local remote_host = host["HostName"]
  local mount_dir = config.mounts.base_dir .. remote_host
  utils.setup_mount_dir(mount_dir, function()
    M.mount_host(host, mount_dir)
  end)
end

M.mount_host = function(host, mount_dir)
  -- Setup new connection
  local remote_host = host["HostName"]

  -- If already connected, disconnect
  if sshfs_job_id then
    -- Kill the SSHFS process
    vim.fn.jobstop(sshfs_job_id)
  end

  -- Construct the SSHFS command
  local sshfs_cmd = "sshfs -o LOGLEVEL=VERBOSE -o ConnectTimeout=5 "

  if config.mounts.unmount_on_exit then
    sshfs_cmd = sshfs_cmd .. "-f "
  end

  if host["Port"] then
    sshfs_cmd = sshfs_cmd .. "-p " .. host["Port"] .. " "
  end

  local user = vim.fn.expand "$USERNAME"
  if host["User"] then
    user = host["User"]
  end
  sshfs_cmd = sshfs_cmd .. user .. "@" .. remote_host

  if host["Path"] then
    sshfs_cmd = sshfs_cmd .. ":" .. host["Path"] .. " "
  else
    sshfs_cmd = sshfs_cmd .. ":/home/" .. user .. "/ "
  end

  sshfs_cmd = sshfs_cmd .. mount_dir

  local function start_job(ask_pass)
    local sshfs_cmd_local = sshfs_cmd
    -- Kill current job (if one exists)
    if sshfs_job_id then
      -- Kill the SSHFS process
      vim.fn.jobstop(sshfs_job_id)
    end

    if ask_pass then
      local password = vim.fn.inputsecret "Enter password for host: "
      sshfs_cmd_local = "echo " .. password .. " | " .. sshfs_cmd .. " -o password_stdin"
    end

    print "Connecting to host..."
    sshfs_job_id = vim.fn.jobstart(sshfs_cmd_local, {
      cwd = mount_dir,
      on_stdout = function(_, data)
        handler.sshfs_wrapper(data, mount_dir, function(event)
          if event == "ask_pass" then
            start_job(true)
          end
        end)
      end,
      on_stderr = function(_, data)
        handler.sshfs_wrapper(data, mount_dir, function(event)
          if event == "ask_pass" then
            start_job(true)
          end
        end)
      end,
      on_exit = function()
        handler.on_exit_handler(mount_dir, function()
          sshfs_job_id = nil
        end)
      end,
    })
  end

  start_job(false)
end

M.unmount_host = function()
  if sshfs_job_id then
    -- Kill the SSHFS process
    vim.fn.jobstop(sshfs_job_id)
  end
end

return M
