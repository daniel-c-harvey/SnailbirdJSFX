require 'Scripts.SnailbirdScripts.include.util';

function GetProjectByName(search_name)
  local index = 0;
  local proj = nil;
  repeat
    proj = reaper.EnumProjects(index);
    if string.starts(reaper.GetProjectName(proj), search_name) then 
      return true, proj;
    end;
    index = index + 1;
  until not proj
  return false, proj;
end
