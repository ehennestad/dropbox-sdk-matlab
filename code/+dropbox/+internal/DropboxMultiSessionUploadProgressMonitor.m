classdef DropboxMultiSessionUploadProgressMonitor < FileTransferProgressMonitor
% DropboxMultipartUploadProgressMonitor - Progress monitor for Dropbox multisession upload

properties
        TotalSize
        Offset = 0
    end

    properties (Access = private)
        PreviousValue = 0;
        TotalValue = 0;
        HasStarted = false
    end

    methods % Constructor
        function obj = DropboxMultiSessionUploadProgressMonitor(totalSize, varargin)
            obj = obj@FileTransferProgressMonitor(varargin)
            obj.TotalSize = totalSize;
        end
    end

    methods
        function obj = getMonitor(obj)
            % Method for returning the object. This will be used as a function
            % handle for the "ProgressMonitorFcn" in matlab.net.http.HTTPOptions
        end

        function quit(obj)
            if ~isempty(obj.WaitbarHandle) && obj.UseWaitbarDialog
                delete(obj.WaitbarHandle);
                obj.WaitbarHandle = [];
            end
            delete(obj)
        end
    end

    methods (Access = protected)
        function update(obj, ~)
            % Override update to take total file size and offset into
            % acconut when displaying progress
            
            import matlab.net.http.*

            if obj.Value < obj.PreviousValue % Reset (new chunk)
                obj.Offset = obj.Offset + obj.PreviousValue;
                obj.PreviousValue = 0;
            end
            obj.TotalValue = obj.Offset + obj.Value;
            
            doUpdate = toc(obj.LastUpdateTime) > obj.UpdateInterval;
            if ~isempty(obj.Value) && doUpdate
                
                if ~obj.HasTransferStarted
                    progressValue = 0;
                    msg = sprintf('Waiting for %s to start...', lower(obj.ActionName));
                    obj.HasTransferStarted = true;
                else
                    progressValue = obj.PercentTransferred / 100;

                    if obj.Direction == MessageType.Request % Sending
                        msg = obj.getProgressMessage();

                    elseif obj.Direction == MessageType.Response
                        % Will receive small amount of data when starting a
                        % chunk transfer (session append). Ignore.
                        return
                    else
                        error('Unknown Messagetype')
                    end
                end

                if isempty(obj.WaitbarHandle) && obj.UseWaitbarDialog
                    % If we don't have a progress bar, display it for first time
                    obj.WaitbarHandle = waitbar(progressValue, msg, ...
                        'Name', obj.getProgressTitle(), ...
                        'CreateCancelBtn', @(~,~) cancelAndClose(obj));
                elseif isempty(obj.PreviousMessage) && obj.UseCommandWindow
                    indentStr = repmat(' ', 1, obj.IndentSize);
                    fprintf('%s%s', indentStr, obj.getProgressTitle() )
                    obj.updateCommandWindowMessage(msg)
                end

                if obj.HasTransferStarted
                    if obj.UseWaitbarDialog
                        waitbar(progressValue, obj.WaitbarHandle, msg);
                    else
                        obj.updateCommandWindowMessage(msg)
                    end
                end

                obj.LastUpdateTime = tic;
            end

            obj.PreviousValue = obj.Value;
        end
          
        function closeWaitbar(~)
            % This is called by done() when a request is finished. However, we
            % need to keep the progress monitor open for the next part/request.
        end

        function percentTransferred = computePercentTransferred(obj)
            percentTransferred = double(obj.TotalValue)/double(obj.TotalSize)*100;
        end

        function fileSizeMb = getFileSizeMb(obj)
            fileSizeMb = round( double(obj.TotalSize) / 1024 / 1024 );
        end

        function transferredMb = getTransferredMb(obj)
            transferredMb = round( double(obj.TotalValue) / 1024 / 1024 );
        end
    end
end
