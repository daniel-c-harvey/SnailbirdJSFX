local DEBUG_OUTPUT = false;

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

function getTracksByName(names)
  foundTracks = {};
  foundTracksCount = 0;
  
  for trackIndex = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, trackIndex)
    local ok, trackName = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
    
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
 
function selectAndArmTracks(tracks)
  if(#tracks > 0)
  then
    reaper.SetOnlyTrackSelected(tracks[1]);
    reaper.SetTrackUIRecArm(tracks[1], 1, 1);
    for index = 2, #tracks do
      track = tracks[index];
      reaper.SetTrackSelected(track, true);
      reaper.SetTrackUIRecArm(track, 1, 1);
    end
  end
end

function muteLooperSends(tracks)
  if(#tracks > 0)
  then
    for index = 1, #tracks do
      track = tracks[index];
      hardSends = reaper.GetTrackNumSends(track, 1);
      for sendIndex = hardSends, reaper.GetTrackNumSends(track, 0) + hardSends - 1 do
        _, sendName = reaper.GetTrackSendName(track, sendIndex);
        _, sendMute = reaper.GetTrackSendUIMute(track, sendIndex);
        if string.starts(string.lower(sendName), "looper") and sendMute == false then
          reaper.ToggleTrackSendUIMute(track, sendIndex);
        end
      end
    end
  end
end

-- The Routine
reaper.defer(function()
--reaper.ShowConsoleMsg(tostring(reaper.GetPlayState()));

-- only bother if we're up and running
if reaper.GetPlayState() ~= 1 then return; end

local LOOP_START = "~LOOP START";
local LOOP_END = "~LOOP END";

local looper_track_names = {"Looper TR-8S Kick Sub", 
                          "Looper TD-3", 
                          "Looper Neutron", 
                          "Looper Minilogue", 
                          "Looper Hydrasynth", 
                          "Looper Pump Buss", 
                          "Looper TR-8S Hands", 
                          "Looper Acid Rain Quadraverb"};
                          
local looper_tracks_found, looper_tracks = getTracksByName(looper_track_names);

if looper_tracks_found then
  reaper.Main_OnCommand(40635, 0); -- Time selection: Remove (unselect) time selection
  
  selectAndArmTracks(looper_tracks);
  
  -- get the transport time and figure out where the next starting point should be
  local playtime = reaper.GetPlayPosition();
  local proj = reaper.EnumProjects(0);
  local beats, current_measure = reaper.TimeMap2_timeToBeats(proj, playtime);
  
  
  -- !!! build in protections about engagin record if we are already looping in the buffer
  timesig_beats, timesig_beat, timesig_tempo = reaper.TimeMap_GetTimeSigAtTime(proj, playtime);
  if beats >= timesig_beats - 1 then current_measure =  current_measure + 1 ; end -- make sure we have time to set up the record
  
  -- translate the bar loop points to time
  -- set looped time selection with those time limits
  
  local loop_length = 8;
  
  -- start record testing, just start at next block of measures
  local start_measure = math.ceil(current_measure / loop_length) * loop_length;
  local end_measure = start_measure + loop_length;
  
  if DEBUG_OUTPUT then
    reaper.ShowConsoleMsg('Start Measre: ' .. tostring(start_measure + 1) .. "\n" ..
                          'End Measure: ' .. tostring(end_measure + 1) .. "\n");
  end
  
  -- Set up the loop time selection
  local start_time = reaper.TimeMap2_beatsToTime(proj, 0, start_measure);
  local end_time = reaper.TimeMap2_beatsToTime(proj, 0, end_measure); 
  reaper.GetSet_LoopTimeRange(1, true, start_time, end_time, false);
  reaper.GetSetRepeat(1);
  reaper.UpdateArrange();
  
  -- set up the recording markers
  --local loop_start_marker_id = reaper.AddProjectMarker(proj, false, start_time, 0, LOOP_START, 98);
  --local loop_end_marker_id = reaper.AddProjectMarker(proj, false, end_time, 0, LOOP_END, 99);
  
  -- Wait until the right before start of the loop
  for measure = current_measure, start_measure - 2 do
    reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0);
  end
 
  
  -- Start the recording
  reaper.Main_OnCommand(40003, 0); -- Transport: Start/stop recording at next measure
  --reaper.Main_OnCommand(1013, 0); -- Transport: Record
  
  for measure = start_measure, end_measure - 1 do
    reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0);
    reaper.Main_OnCommand(2009, 0); -- Action: Wait 0.5 seconds before next action
    if DEBUG_OUTPUT then reaper.ShowConsoleMsg(tostring(measure + 1) .. " "); end
  end  
  
  -- Stop the recording and let it ride
  reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0); 
  reaper.Main_OnCommand(40003, 0); -- Transport: Start/stop recording at next measure
  
  -- wait to pass over the end of the recording 
  --while reaper.GetPlayState() & 4 ~= 0 do
  --  reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0);
  --end
  
  --reaper.Main_OnCommand(2008, 0); -- Action: Wait 0.1 seconds before next action
  
  -- Mute Sends to the looper so passthrough audio is overridden by the recorded audio
  local mixer_track_names = {"TR-8S Kick Sub Mixer",
                             "TD-3 Mixer",
                             "Neutron Mixer",
                             "Minilogue Mixer",
                             "Hydrasynth Mixer",
                             "Pump Buss Mixer",
                             "TR-8S Hands Mixer",
                             "Acid Rain Quadraverb Mixer"};
  
  mixer_tracks_found, mixer_tracks = getTracksByName(mixer_track_names);
  if mixer_tracks_found then
    muteLooperSends(mixer_tracks);
  else
    reaper.ShowConsoleMsg("Mixer Tracks not found\n");
  end
  
  reaper.UpdateArrange();
else
  reaper.ShowConsoleMsg("Looper Tracks not found\n");
end
end);

