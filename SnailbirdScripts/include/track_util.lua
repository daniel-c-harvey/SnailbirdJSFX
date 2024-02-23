require 'Scripts.SnailbirdScripts.include.util';

function GetTracksByName(proj, names)
  local foundTracks = {};
  local foundTracksCount = 0;
  
  for trackIndex = 0, reaper.CountTracks(proj) - 1 do
    track = reaper.GetTrack(proj, trackIndex);
    ok, trackName = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false);
    reaper.ShowConsoleMsg(trackName .. "\n");
    if ok then
      -- check if this track matches any of our names
      for nameIndex = 1, #names do
        local name = names[nameIndex];
        if trackName == name then
          foundTracks[nameIndex] = track -- found it!
          foundTracksCount = foundTracksCount + 1;
          if foundTracksCount >= #names then 
              return true, foundTracks; -- found all, abort early
          end
        end
      end
    end
  end
  return false, foundTracks; -- we only get here if we didn't find everyone
end

function SelectAndArmTracks(tracks)
  if(#tracks > 0)
  then
      reaper.SetOnlyTrackSelected(tracks[1]);
      reaper.SetTrackUIRecArm(tracks[1], 1, 1);
      for index = 2, #tracks do
      local track = tracks[index];
      reaper.SetTrackSelected(track, true);
      reaper.SetTrackUIRecArm(track, 1, 1);
      end
  end
end
    
