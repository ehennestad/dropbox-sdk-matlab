classdef DropboxApiClient < handle & matlab.mixin.CustomDisplay
% DropboxFileApiClient - API client for Dropbox file API endpoints 


% See also:
% https://www.dropbox.com/developers/documentation/http/documentation


    properties
        ServerURL matlab.net.URI = "https://api.dropboxapi.com/2"
        %HttpOptions = matlab.net.http.HTTPOptions; Todo??
    end

    properties
        LocalDropboxFolder % reconsider if this prop belongs here or elsewhere
    end

    properties
        TeamConfiguration (1,1) dropbox.enum.TeamConfiguration = "TeamFolders"
        CurrentFolder (1,1) string = missing
    end

    properties (Access = private)
        RPCEndpointDomainBaseUrl = ...
            "https://api.dropboxapi.com"

        ContentEndpointDomainBaseURL = ...
            "https://content.dropboxapi.com"

        API_VERSION = "2"
    end

    properties (Dependent, Hidden)
        AccessToken
    end

    properties (Access = private)
        Dropbox_API_Path_Root (1,1) string = missing
        AuthClient dropbox.internal.AuthorizationClient
        HasOpenUploadSession (1,1) logical = false
    end

    properties (Constant, Access = private)
        MAX_CHUNK_SIZE = 150 * 2^20; % 150MiB, for upload sessions
    end

    methods % Constructor
        function obj = DropboxApiClient()
            import dropbox.internal.AuthorizationClient
            obj.AuthClient = AuthorizationClient.instance();
            if ismissing(obj.AuthClient.AccessToken)
                obj.AuthClient.fetchToken();
            end
        end
    end

    methods % Set/get methods for properties
        function result = get.AccessToken(obj)
            result = obj.AuthClient.AccessToken;
        end
        function set.TeamConfiguration(obj, value)
            obj.TeamConfiguration = value;
            obj.postSetTeamConfiguration()
        end        
    end

    methods % Methods for downloading / uploading with progress monitor
        function downloadedFilePath = downloadFile(obj, filePath, targetFolder)
            arguments
                obj
                filePath (1,1) string = ""
                targetFolder (1,1) string = pwd
            end
            filePath = obj.validatePathName(filePath);
            fileLinkURL = obj.getTemporaryDownloadLink(filePath);
            
            folder = fullfile(targetFolder, fileparts(filePath));
            if ~isfolder(folder); mkdir(folder); end
            strLocalFilename = fullfile(targetFolder, filePath);

            downloadedFilePath = downloadFile(strLocalFilename, fileLinkURL);
        end

        function uploadFile(obj, filePathLocal, filePathRemote, options)
            arguments
                obj
                filePathLocal (1,1) string {mustBeFile}
                filePathRemote (1,1) string
                options.AutoRename (1,1) logical = false
                options.Mode (1,1) string ...
                    {mustBeMember(options.Mode, ["add", "overwrite", "update"])} = "add"
                options.Mute (1,1) logical = false
                options.StrictConflict (1,1) logical = false
            end
            filePathLocal = obj.validatePathName(filePathLocal);

            L = dir(filePathLocal);
            totalSize = L.bytes;

            optionalNvPairs = namedargs2cell(options);

            if totalSize < obj.MAX_CHUNK_SIZE
                fileLinkURL = obj.getTemporaryUploadLink(filePathRemote, optionalNvPairs{:});
    
                % Create a RequestMessage tailored to dropbox' api
                method = matlab.net.http.RequestMethod.POST;
                contentTypeField = matlab.net.http.field.ContentTypeField(...
                    matlab.net.http.MediaType("application/octet-stream"));
                req = matlab.net.http.RequestMessage(method, contentTypeField, []);
    
                uploadFile(filePathLocal, fileLinkURL, "RequestMessage", req)
            else
                obj.multipartUpload(filePathLocal, filePathRemote, optionalNvPairs{:})
            end
        end
    end

    methods % API Methods
        function result = listFolder(obj, folderPath, options)
        % listFolder - List contents of a folder given a path name

            arguments
                obj
                folderPath (1,1) string = ""
                options.IncludeDeleted (1,1) logical = false
                options.IncludeHasExplicitSharedMembers (1,1) logical = true
                options.IncludeMountedFolders (1,1) logical = true
                options.IncludeNonDownloadableFiles (1,1) logical = true
                options.Recursive (1,1) logical = false
            end
                       
            folderPath = obj.validatePathName(folderPath);

            parameters = struct( ...
                "include_deleted", options.IncludeDeleted, ...
                "include_has_explicit_shared_members", options.IncludeHasExplicitSharedMembers, ...
                "include_mounted_folders", options.IncludeMountedFolders, ...
                "include_non_downloadable_files", options.IncludeNonDownloadableFiles, ...
                "path", folderPath, ...
                "recursive", options.Recursive ...
            );

            apiEndpoint = obj.getRPCEndpointURL("files/list_folder");
            responseData = obj.postRPC(apiEndpoint, parameters);
            result = responseData.entries;
        end

        function result = createFolder(obj, folderPath, options)
        % createFolder - Create a folder at a given path.
            arguments
                obj
                folderPath (1,1) string = ""
                options.AutoRename (1,1) logical = false
            end
                       
            folderPath = obj.validatePathName(folderPath);

            parameters = struct( ...
                "autorename", options.AutoRename, ...
                "path", folderPath ...
            );    

            apiEndpoint = obj.getRPCEndpointURL("files/create_folder_v2");
            responseData = obj.postRPC(apiEndpoint, parameters);
            result = responseData.metadata;
            if ~nargout
                clear result
            end
        end

        function result = getMetadata(obj, pathName, options)
        % getMetadata - Get metadata for a file/folder given it's path name
            arguments
                obj
                pathName (1,1) string = ""
                options.IncludeDeleted (1,1) logical = false
                options.IncludeHasExplicitSharedMembers (1,1) logical = true
                options.IncludeMediaInfo (1,1) logical = false
            end

            pathName = obj.validatePathName(pathName);

            parameters = struct( ...
                "include_deleted", options.IncludeDeleted, ...
                "include_has_explicit_shared_members", options.IncludeHasExplicitSharedMembers, ...
                "include_media_info", false, ...
                "path", pathName ...
            );
                        
            apiEndpoint = obj.getRPCEndpointURL("files/get_metadata");
            responseData = obj.postRPC(apiEndpoint, parameters);
            result = responseData;
        end
        
        function [result, cursor] = search(obj, searchTerm, folderToSearchIn, options)

            arguments
                obj
                searchTerm (1,1) string
                folderToSearchIn (1,1) string = ""
                options.IncludeHighlights (1,1) logical = false
                options.FileStatus (1,1) string {mustBeMember(options.FileStatus, ["active", "deleted"])} = "active"
                options.FilenameOnly (1,1) logical = false
                options.MaxResults (1,1) double = 100
            end
            folderToSearchIn = obj.validatePathName(folderToSearchIn);
            
            parameters = struct(...
                "match_field_options", struct(...
                    "include_highlights", options.IncludeHighlights ...
                ), ...
                "options", struct(...
                    "file_status", options.FileStatus, ...
                    "filename_only", options.FilenameOnly, ...
                    "max_results", options.MaxResults, ...
                    "path", folderToSearchIn ...
                ), ...
                "query", searchTerm ...
            );

            apiEndpoint = obj.getRPCEndpointURL("files/search_v2");
            responseData = obj.postRPC(apiEndpoint, parameters);
            result = responseData.matches;
            if nargout == 2
                if responseData.has_more
                    cursor = responseData.cursor;
                else
                    cursor = string.empty;
                end
            end
        end

        function [result, cursor] = continueSearch(obj, cursor)
            arguments
                obj
                cursor (1,1) string
            end

            parameters = struct('cursor', cursor);

            apiEndpoint = obj.getRPCEndpointURL("files/search/continue_v2");
            responseData = obj.postRPC(apiEndpoint, parameters);
            result = responseData.matches;
            if nargout == 2
                if responseData.has_more
                    cursor = responseData.cursor;
                else
                    cursor = string.empty;
                end
            end
        end

        function result = move(obj, sourcePath, destinationPath, options)
        % move - Move a file or folder to a different location in the user's Dropbox. 
        % 
        % If the source path is a folder all its contents will be moved. 
        % Note that case-only renaming is currently not supported.
        
            arguments
                obj
                sourcePath (1,1) string
                destinationPath (1,1) string
                options.AllowOwnershipTransfer (1,1) logical = false
                options.Autorename (1,1) logical = false
            end            
            
            sourcePath = obj.validatePathName(sourcePath);
            destinationPath = obj.validatePathName(destinationPath);

            options = namedargs2cell(options);
            result = obj.transfer("move", sourcePath, destinationPath, options{:});
        end

        function result = copy(obj, sourcePath, destinationPath, options)
        % copy - Copy a file or folder to a different location in the user's Dropbox. 
        % 
        %  If the source path is a folder all its contents will be copied.

            arguments
                obj
                sourcePath (1,1) string
                destinationPath (1,1) string
                options.AllowOwnershipTransfer (1,1) logical = false
                options.Autorename (1,1) logical = false
            end            
            
            sourcePath = obj.validatePathName(sourcePath);
            destinationPath = obj.validatePathName(destinationPath);

            options = namedargs2cell(options);
            result = obj.transfer("copy", sourcePath, destinationPath, options{:});
        end
        
        function responseData = downloadFileContent(obj, filePath)
            arguments
                obj
                filePath (1,1) string = ""
            end
            
            filePath = obj.validatePathName(filePath);

            parameters = struct( ...
                "path", filePath ...
                );

            apiEndpoint = obj.getContentEndpointURL("files/download");
            responseData = obj.postContent(apiEndpoint, parameters, []);
        end

        function fileLinkURL = getTemporaryDownloadLink(obj, filePath)
            arguments
                obj
                filePath (1,1) string
            end
            filePath = obj.validatePathName(filePath);
            parameters = struct('path', filePath);

            apiEndpoint = obj.getRPCEndpointURL("files/get_temporary_link");
            responseData = obj.postRPC(apiEndpoint, parameters);
            fileLinkURL = responseData.link;
        end

        function fileLinkURL = getTemporaryUploadLink(obj, filePath, options)
            arguments
                obj
                filePath (1,1) string
                options.AutoRename (1,1) logical = true
                options.Mode (1,1) string ...
                    {mustBeMember(options.Mode, ["add", "overwrite", "update"])} = "add"
                options.Mute (1,1) logical = false
                options.StrictConflict (1,1) logical = false
                options.Duration (1,1) double = 14400 % seconds
            end
            filePath = obj.validatePathName(filePath);

            parameters = struct(...
                "commit_info", struct(...
                    "autorename", options.AutoRename, ...
                    "mode", options.Mode, ...
                    "mute", options.Mute, ...
                    "path", filePath, ...
                    "strict_conflict", options.StrictConflict ...
                ), ...
                "duration", options.Duration ...
            );

            apiEndpoint = obj.getRPCEndpointURL("files/get_temporary_upload_link");
            responseData = obj.postRPC(apiEndpoint, parameters);
            fileLinkURL = responseData.link;
        end
    end

    % uploadFile will use the following endpoints if the file size is
    % larger than 150 MiB. Keeping as Hidden instead of Private so that
    % these methods are available for advanced use cases.
    methods (Hidden) % Hidden API endpoints 
        function uploadSessionID = uploadSessionStart(obj)

            parameters = struct( ...
                "close", false ...
                );

            apiEndpoint = obj.getContentEndpointURL("files/upload_session/start");
            responseData = obj.postContent(apiEndpoint, parameters);
            uploadSessionID = responseData.session_id;
        end

        function uploadSessionID = uploadSessionAppend(obj, uploadSessionID, dataProvider, offset, options)
            arguments
                obj
                uploadSessionID (1,1) string
                dataProvider = matlab.net.http.io.ContentProvider.empty
                offset (1,1) uint64 = 0
                options.WebOptions matlab.net.http.HTTPOptions = matlab.net.http.HTTPOptions.empty % Todo: Use client property instead of passing???
                options.AbortSession (1,1) logical = false
            end
           
            parameters = struct( ...
               'cursor', struct( ...
                   'session_id', uploadSessionID, ...
                   'offset', offset ...
               ), ...
               'close', options.AbortSession ...
            );

            apiEndpoint = obj.getContentEndpointURL("files/upload_session/append_v2");
            obj.postContent(apiEndpoint, parameters, dataProvider, ...
                "WebOptions", options.WebOptions);
        end

        function uploadSessionFinish(obj, uploadSessionID, dataProvider, offset, dropBoxFilePath, uploadOptions, options)
            arguments
                obj
                uploadSessionID (1,1) string
                dataProvider = matlab.net.http.io.ContentProvider.empty
                offset (1,1) uint64 = 0
                dropBoxFilePath (1,1) string = "missing"
                uploadOptions.?dropbox.options.CommitInfo
                options.WebOptions matlab.net.http.HTTPOptions = matlab.net.http.HTTPOptions.empty
            end
           
            dropBoxFilePath = obj.validatePathName(dropBoxFilePath);

            parameters = struct( ...
                'cursor', struct( ...
                    'session_id', uploadSessionID, ...
                    'offset', offset ...
                ), ...
                'commit', struct( ...
                    'path', dropBoxFilePath, ...
                    'mode', uploadOptions.Mode, ... 
                    'autorename', uploadOptions.AutoRename, ...
                    'mute', uploadOptions.Mute, ...
                    'strict_conflict', uploadOptions.StrictConflict ...
                ) ...
            );

            apiEndpoint = obj.getContentEndpointURL("files/upload_session/finish");
            obj.postContent(apiEndpoint, parameters, dataProvider, ...
                "WebOptions", options.WebOptions);
        end
    end

    methods (Access = private) % Internal utility methods for API requests
        function endpointURL = getRPCEndpointURL(obj, endPointPath)
            arguments
                obj (1,1) dropbox.DropboxApiClient
                endPointPath (1,1) string
            end

            endpointURL = strjoin([ ...
                obj.RPCEndpointDomainBaseUrl, ...
                obj.API_VERSION, ...
                endPointPath], "/" );
        end

        function endpointURL = getContentEndpointURL(obj, endPointPath)
            arguments
                obj (1,1) dropbox.DropboxApiClient
                endPointPath (1,1) string
            end

            endpointURL = matlab.net.URI( strjoin([ ...
                obj.ContentEndpointDomainBaseURL, ...
                obj.API_VERSION, ...
                endPointPath], "/" ) );
        end

        function result = postRPC(obj, apiEndpointUrl, parameters)
            arguments
                obj (1,1)
                apiEndpointUrl (1,1) matlab.net.URI
                parameters (1,:) struct = struct.empty
            end

            method = matlab.net.http.RequestMethod.POST;
            headers = obj.getRPCHeader();
            if ~isempty(parameters)
                body = matlab.net.http.MessageBody(parameters);
            else
                body = matlab.net.http.MessageBody.empty;
                isContentTypeField = arrayfun(@(x) isa(x, 'matlab.net.http.field.ContentTypeField'), headers);
                headers(isContentTypeField)=[];

                warnState = warning('off', 'MATLAB:http:BodyExpectedFor');
                warningCleanup = onCleanup(@(ws) warning(warnState));
            end

            req = matlab.net.http.RequestMessage(method, headers, body);
            response = req.send(apiEndpointUrl);
            result = obj.processResponse(response);
        end
        
        function result = postContent(obj, apiEndpointUrl, parameters, data, options)
            arguments
                obj (1,1)
                apiEndpointUrl (1,1) matlab.net.URI
                parameters (1,:) struct = struct.empty
                data = []
                options.WebOptions matlab.net.http.HTTPOptions = matlab.net.http.HTTPOptions.empty
            end

            if isempty(data)
                warnState = warning('off', 'MATLAB:http:BodyExpectedFor');
                warningCleanup = onCleanup(@(ws) warning(warnState));
            end

            if isa(data, 'matlab.net.http.io.ContentProvider')
                body = data;
            else
                body = matlab.net.http.MessageBody(data);
            end

            method = matlab.net.http.RequestMethod.POST;
            headers = obj.getContentHeader(parameters);
            req = matlab.net.http.RequestMessage(method, headers, body);
        
            response = req.send(apiEndpointUrl, options.WebOptions);

            result = obj.processResponse(response);
        end

        function headers = getRPCHeader(obj)
            authorizationField = obj.AuthClient.getAuthHeaderField();
            acceptField = matlab.net.http.field.AcceptField("application/json");
            contentTypeField = matlab.net.http.field.ContentTypeField("application/json");
            
            headers = [authorizationField, acceptField, contentTypeField];

            if ~ismissing(obj.Dropbox_API_Path_Root)
                headers = [headers, obj.getDropboxApiPathRootHeaderField() ];
            end
        end
    
        function headers = getContentHeader(obj, parameters)
            import matlab.net.http.HeaderField
            import matlab.net.http.field.ContentTypeField
            import matlab.net.http.MediaType

            authorizationField = obj.AuthClient.getAuthHeaderField();
            dropboxArgHeader = HeaderField('Dropbox-API-Arg', jsonencode(parameters));
            contentTypeField = ContentTypeField(MediaType("application/octet-stream"));

            headers = [dropboxArgHeader, authorizationField, contentTypeField];

            if ~ismissing(obj.Dropbox_API_Path_Root)
                headers = [headers, obj.getDropboxApiPathRootHeaderField() ];
            end
        end

        function result = processResponse(~, response)
            if response.StatusCode == "OK"
                result = response.Body.Data;
            else
                if isstruct(response.Body.Data)
                    error('%s: %s', response.StatusCode, response.Body.Data.error_summary)
                else
                    error('%s: %s', response.StatusCode, response.Body.Data)
                end
            end
        end

        function headerField = getDropboxApiPathRootHeaderField(obj)
            jsonStr = sprintf('{".tag": "root", "root": "%s"}', obj.Dropbox_API_Path_Root);
            headerField = matlab.net.http.HeaderField('Dropbox-API-Path-Root', jsonStr);
        end
    end

    methods (Access = private) % Multipart upload
            
        function result = transfer(obj, mode, sourcePath, destinationPath, options)
        % transfer - Move or copy folders or files
        %
        % See also move, copy

            arguments
                obj
                mode (1,1) string {mustBeMember(mode, ["copy", "move"])}
                sourcePath (1,1) string
                destinationPath (1,1) string
                options.AllowOwnershipTransfer (1,1) logical = false
                options.Autorename (1,1) logical = false
            end
                       
            sourcePath = obj.validatePathName(sourcePath);
            destinationPath = obj.validatePathName(destinationPath);

            data = struct( ...
                'allow_ownership_transfer', options.AllowOwnershipTransfer, ...
                'allow_shared_folder',      false, ... % deprecated
                'autorename',               options.Autorename, ...
                'from_path',                sourcePath, ...
                'to_path',                  destinationPath ...
                );
            
            endpointPath = sprintf("files/%s_v2", mode);
            apiEndpoint = obj.getRPCEndpointURL(endpointPath);
            responseData = obj.postRPC(apiEndpoint, data);
            result = responseData;
        end

        function multipartUpload(obj, filePath, dropBoxFilePath, uploadOptions, options)
            arguments 
                obj
                filePath               char         %{mustBeValidUrl}
                dropBoxFilePath        (1,1) string
                uploadOptions.?dropbox.options.CommitInfo
                options.DisplayMode    char         {mustBeValidDisplay} = 'Dialog Box'
                options.UpdateInterval (1,1) double {mustBePositive}     = 1
                options.ShowFilename   (1,1) logical                     = false
                options.IndentSize     (1,1) uint8                       = 0
                options.RequestMessage matlab.net.http.RequestMessage    = matlab.net.http.RequestMessage.empty
            end

            if options.ShowFilename
                [~, filename, ext] = fileparts(strURLFilename);
                filename = [char(filename), char(ext)];
            else
                filename = '';
            end

            % Get file size
            L = dir(filePath);
            totalBytes = L.bytes;

            uploadSessionID = obj.uploadSessionStart();
            obj.HasOpenUploadSession = true;
            cleanUpObj = onCleanup(@(varargin) obj.closeUploadSession(uploadSessionID));

            % Create ProgressMonitor
            monitorOpts = {...
                'DisplayMode', options.DisplayMode, ...
                'UpdateInterval', options.UpdateInterval, ...
                'Filename', filename, ...
                'IndentSize', options.IndentSize };
            
            progressMonitor = dropbox.internal.DropboxMultiSessionUploadProgressMonitor(...
                totalBytes, monitorOpts{:});
            progressMonitorCleanupObj = onCleanup(@progressMonitor.quit);

            webOpts = matlab.net.http.HTTPOptions(...
                'ProgressMonitorFcn', @(varargin) getMonitor(progressMonitor), ...
                'UseProgressMonitor', true, ...
                'ConnectTimeout', 20);

            % Get chunks
            chunkSize = obj.MAX_CHUNK_SIZE;
            offset = uint64(0);
            numChunks = ceil(totalBytes / chunkSize);

            dataProvider = dropbox.internal.MultiPartFileProvider(filePath, totalBytes, chunkSize);
            providerCleanupObj = onCleanup(@(h) delete(dataProvider));

            for i = 1:numChunks
                
                if i == numChunks
                    chunkSize = totalBytes - (numChunks-1)*chunkSize;
                end
                    
                if i < numChunks
                    obj.uploadSessionAppend(uploadSessionID, dataProvider, offset, "WebOptions", webOpts);
                else
                    nvPairs = namedargs2cell(uploadOptions);
                    obj.uploadSessionFinish(uploadSessionID, dataProvider, offset, dropBoxFilePath, "WebOptions", webOpts, nvPairs{:});
                    obj.HasOpenUploadSession = false;
                end
                %drawnow

                offset = offset + chunkSize;
                dataProvider.resetCount()
            end
        end

        function closeUploadSession(obj, uploadSessionID)
            if obj.HasOpenUploadSession
                obj.uploadSessionAppend(uploadSessionID, "AbortSession", true);
                disp('Aborted upload session')
                obj.HasOpenUploadSession = false;
            end
        end
    end

    methods (Access = private) % Property post set methods 
        function postSetTeamConfiguration(obj)

            switch obj.TeamConfiguration
                case "TeamSpace"
                    apiEndpoint = obj.getRPCEndpointURL("users/get_current_account");
                    responseData = obj.postRPC(apiEndpoint, []);
                    obj.Dropbox_API_Path_Root = responseData.root_info.root_namespace_id;
                case "TeamFolders"
                    obj.Dropbox_API_Path_Root = missing;
            end
        end
    end

    methods (Static, Access = private)
        function result = getItemByName(entries, name)
            allNames = cellfun(@(c) string(c.name), entries);
            isMatch = strcmp(allNames, name);
            result = entries{isMatch};
        end

        function pathName = validatePathName(pathName)
            if strlength(pathName) > 0
                if ~startsWith(pathName, "/")
                    pathName = "/" + pathName;
                end
                if endsWith(pathName, "/")
                    pathName = extractBefore(pathName, strlength(pathName));
                end
                               
                pathName = strtrim(pathName);
            end
        end
    end
end

%% Custom validation functions

function mustBeValidDisplay(displayName)
    mustBeMember(displayName, {'Dialog Box', 'Command Window'})
end
