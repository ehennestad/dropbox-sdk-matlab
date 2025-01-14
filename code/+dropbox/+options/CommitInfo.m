classdef CommitInfo
    properties

        Mode (1,1) string ...
            {mustBeMember(Mode, ["add", "overwrite", "update"])} = "add"

        AutoRename (1,1) logical = true
        
        Mute (1,1) logical = false
        
        % ClientModified Not implemented
    
        % PropertyGroups Not implemented

        StrictConflict (1,1) logical = false
    end
end
