--[[
    Copyright (C) 2026 Andrew Raub <raublekick@gmail.com>.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
    file_cleanup.lua
    find files that do not exist in the library database

    Perform maintenance to clean up images that do not exist in the library. 
    This can be useful for cases where files have been deleted from the 
    library but not from the disk. 

    ADDITIONAL SOFTWARE NEEDED FOR THIS SCRIPT
    None

    USAGE
    * start file cleanup from script_manager
    * scan for files that are missing from the library
    * look at the results and choose to delete or not

    CHANGES
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local log = require "lib/dtutils.log"


-- - - - - - - - - - - - - - - - - - - - - - - - 
-- C O N S T A N T S
-- - - - - - - - - - - - - - - - - - - - - - - - 

local MODULE <const> = "file_cleanup"
local DEFAULT_LOG_LEVEL <const> = log.debug
local PS <const> = dt.configuration.running_os == "windows" and "\\" or "/"
local LS_COMMAND <const> = dt.configuration.running_os == "windows" and "dir" or "ls"

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- A P I  C H E C K
-- - - - - - - - - - - - - - - - - - - - - - - - 

du.check_min_api_version("7.0.0", MODULE)   -- choose the minimum version that contains the features you need


-- - - - - - - - - - - - - - - - - - - - - - - - - -
-- I 1 8 N
-- - - - - - - - - - - - - - - - - - - - - - - - - -

local gettext = dt.gettext.gettext

local function _(msgid)
    return gettext(msgid)
end


-- - - - - - - - - - - - - - - - - - - - - - - - - -
-- S C R I P T  M A N A G E R  I N T E G R A T I O N
-- - - - - - - - - - - - - - - - - - - - - - - - - -

local script_data = {}

script_data.destroy = nil           -- function to destory the script
script_data.destroy_method = nil    -- set to hide for libs since we can't destroy them commpletely yet
script_data.restart = nil           -- how to restart the (lib) script after it's been hidden - i.e. make it visible again
script_data.show = nil              -- only required for libs since the destroy_method only hides them

script_data.metadata = {
  name = _("file cleanup"),
  purpose = _("find files that do not exist in the library database"),
  author = "Andrew Raub <raublekick@gmail.com>",
  help = "https://docs.darktable.org/lua/stable/lua.scripts.manual/scripts/contrib/file_cleanup/"
}


-- - - - - - - - - - - - - - - - - - - - - - - - 
-- L O G  L E V E L
-- - - - - - - - - - - - - - - - - - - - - - - - 

log.log_level(DEFAULT_LOG_LEVEL)

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- N A M E  S P A C E
-- - - - - - - - - - - - - - - - - - - - - - - - 

local file_cleanup = {}

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- G L O B A L  V A R I A B L E S
-- - - - - - - - - - - - - - - - - - - - - - - - 

file_cleanup.main_widget = nil

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- A L I A S E S
-- - - - - - - - - - - - - - - - - - - - - - - - 

local namespace = file_cleanup

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- F U N C T I O N S
-- - - - - - - - - - - - - - - - - - - - - - - - 

-------------------
-- helper functions
-------------------

local function set_log_level(level)
  local old_log_level = log.log_level()
  log.log_level(level)
  return old_log_level
end

local function restore_log_level(level)
  log.log_level(level)
end

local function list_dir(path)
  local cmd
  if dt.configuration.running_os == "windows" then
    cmd = 'dir /b /a-d "' .. path .. '"'
  else
    cmd = 'find "' .. path.. '" -maxdepth 1 -type f'
  end
  local files = {}
  local p = io.popen(cmd, "r")
  if p then
    for line in p:lines() do files[#files + 1] = line end
    p:close()
  end
  return files
end

local function strip_xmp(name)
  return (name:gsub("%.[xX][mM][pP]$", ""))
end

local function scan_film_rolls()
  local missing_files = {}

  for _, filmroll in ipairs(dt.films) do
    if df.check_if_file_exists(filmroll.path) then
      -- get contents of path
      local files = list_dir(filmroll.path)
      local in_library = {}

      for _, image in ipairs(filmroll) do 
        local full_path = image.path .. PS .. image.filename
        -- log.msg(log.debug, "Adding from library " .. full_path)
        in_library[full_path] = true
      end

      for _, file in ipairs(files) do 
        -- if the file is an xmp, see if the corresponding image is in the library or if it's orphaned
        -- if it's an image, just check if it's in the library

        -- if(file:lower():match("20261021_0026")) 
        -- then
        --     log.msg(log.debug, "file in library " .. tostring(in_library[file]))
        --     log.msg(log.debug, "file " .. file)
        --     log.msg(log.debug, "chopped " .. df.chop_filetype(file))
        -- end
        if 
          (file:lower():match("%.xmp$") ~= nil and not in_library[df.chop_filetype(file)]) or
          (file:lower():match("%.xmp$") == nil and not in_library[file])
        then
          log.msg(log.debug, "found " .. file)
          table.insert(missing_files, file)
        end
      end
    end
  end

  return missing_files
end

local function install_module()
  if not namespace.module_installed then
    dt.register_lib(
      MODULE,     -- Module name
      _("File Cleanup"),     -- Visible name
      true,                -- expandable
      true,               -- resetable
      {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_LEFT_CENTER", 0}},   -- containers
      namespace.main_widget,
      nil,-- view_enter
      nil -- view_leave
    )
    namespace.module_installed = true
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- U S E R  I N T E R F A C E
-- - - - - - - - - - - - - - - - - - - - - - - - 

file_cleanup.list_widget = dt.new_widget("text_view"){
  editable = false,
  reset_callback = function(this)
    this.text = ""
  end
}

file_cleanup.scan_button = dt.new_widget("button"){
  label = _("scan"),
  tooltip = _("click to scan for missing film rolls/files"),
  clicked_callback = function(this)
    local found = nil
    local found_text = ""
    local old_log_level = set_log_level(DEFAULT_LOG_LEVEL)
    log.msg(log.debug, "Button clicked")
    
    found = scan_film_rolls()
    if #found > 0 then
      for _, file in ipairs(found) do
        local dir_name = du.split(file, PS)
        found_text = found_text .. dir_name[#dir_name] .. "\n"
      end
    end
    
    if #found > 0 then
      log.msg(log.debug, "found " .. #found .. " missing items")
      file_cleanup.list_widget.text = found_text
      file_cleanup.found = found
    else
      log.msg(log.debug, "no missing items found")
    end
    restore_log_level(old_log_level)
  end,
  reset_callback = function(this)
    file_cleanup.found = nil
  end
}

file_cleanup.main_widget = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("section_label"){label = _("missing items")},
  file_cleanup.list_widget,
  dt.new_widget("label"){label = ""},
  file_cleanup.scan_button,
  -- file_cleanup.remove_button
}

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- D A R K T A B L E  I N T E G R A T I O N 
-- - - - - - - - - - - - - - - - - - - - - - - - 

local function destroy()
  dt.gui.libs[MODULE].visible = false

  if namespace.event_registered then
    dt.destroy_event(MODULE, "view-changed")
  end

  return
end

local function restart()
  dt.gui.libs[MODULE].visible = true

  return
end

script_data.destroy = destroy
script_data.restart = restart
script_data.destroy_method = "hide"
script_data.show = restart

-- - - - - - - - - - - - - - - - - - - - - - - - 
-- E V E N T S
-- - - - - - - - - - - - - - - - - - - - - - - - 

if dt.gui.current_view().id == "lighttable" then
  install_module()
else
  if not namespace.event_registered then
    dt.register_event(MODULE, "view-changed",
      function(event, old_view, new_view)
        if new_view.name == "lighttable" and old_view.name == "darkroom" then
          install_module()
         end
      end
    )
    namespace.event_registered = true
  end
end

return script_data