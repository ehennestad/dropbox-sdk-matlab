classdef AuthorizationClient < handle
% AuthorizationClient - Singleton client for PKCE authorization flow
%
%   Syntax:
%       authClient = dropbox.internal.AuthorizationClient.instance() 
%           creates a client or retrieves an existing (persistent) client
%
%       authClient = dropbox.internal.AuthorizationClient.instance(clientId) 
%           creates a client or retrieves an existing (persistent) client
%           using the client id of a Dropbox app of your choice.
%
%       authClient.fetchToken() redirects to the browser to Dropbox for user to 
%           grant permissions
%
%   Methods:
%       This class provides the following utility methods for getting header 
%       fields or weboptions with the value of the Authorization field set to 
%       Bearer <Token> using the access token stored in this client:
%           - getAuthHeaderField
%           - getWebOptions
%
%   Description:
%       This client uses a Dropbox app to retrieve an access token for a user 
%       account via the PKCE authorization flow. The first time you need a 
%       token, the client opens a web page in your browser. You must then 
%       authorize the Matlab-API-Client and copy the resulting authorization 
%       code. Finally, paste that code into the MATLAB input dialog that appears.
%
%       Alternatively, you can use your own Dropbox app instead.

    properties (Constant, Access = private)
        % Default MATLAB API APP client ID. To use your own client ID, provide
        % clientID as an input when your create the singleton instance.
        MATLAB_API_CLIENT_ID = "ni580y32gjn902a"
    end
    
    properties (Dependent, SetAccess = private)
        AccessToken
        TokenExpiresIn
    end

    properties (Access = private)
        AccessToken_ (1,1) string = missing
        RefreshToken_ (1,1) string = missing
        AccessTokenExpiresAt
    end

    properties (SetAccess = immutable, GetAccess = private)
        DropboxAppClientID (1,1) string = missing
    end


    properties (Constant, Access = private)
        SINGLETON_NAME = "Dropbox_Authorization_Client"

        AUTH_URL = ...
            "https://www.dropbox.com/oauth2/authorize"

        TOKEN_URL = ...
            "https://api.dropboxapi.com/oauth2/token"
    end
    
    methods (Access = private)
        function obj = AuthorizationClient(clientID)
        % AuthorizationClient - Constructor, see also instance() method
            arguments
                clientID (1,1) string = missing
            end
            if ismissing(clientID)
                obj.DropboxAppClientID = obj.MATLAB_API_CLIENT_ID;
            else
                obj.DropboxAppClientID = clientID;
            end

            % Try to load an old refresh token from matlab's secrets / prefs
            obj.loadRefreshTokenFromPreviousSession()
            
            obj.refreshToken()

            if ~nargout
                clear obj
            end
        end
    end

    methods
        function remainingTime = get.TokenExpiresIn(obj)
            if isempty(obj.AccessTokenExpiresAt)
                remainingTime = NaT;
            else
                currentTime = datetime("now");
                remainingTime = obj.AccessTokenExpiresAt - currentTime;
            end
        end

        function accessToken = get.AccessToken(obj)
            if ismissing(obj.AccessToken_)
                obj.fetchToken()
            elseif obj.TokenExpiresIn < seconds(10)
                try
                    obj.updateTokenFromRefreshToken()
                catch
                    obj.fetchToken()
                end
            end
            accessToken = obj.AccessToken_;
        end
    end

    methods
        function opts = getWebOptions(obj, opts)
        % getWebOptions - Get weboptions object with authorization header
        %
        % Syntax:
        %  opts = authClient.getWebOptions() returns a weboptions object
        %  containing an Authorization header field with value Bearer <TOKEN>
        %
        %  opts = authClient.getWebOptions(opts) appends an Authorization header
        %  field with value Bearer <TOKEN> to an existing weboptions object

            arguments
                obj
                opts weboptions = weboptions
            end

            opts.HeaderFields = [ opts.HeaderFields, ...
                "Authorization", sprintf("Bearer %s", obj.AccessToken)];
        end

        function authField = getAuthHeaderField(obj)
        % getAuthHeaderField - Get AuthorizationField object with BearerToken
        %
        % Syntax:
        %  opts = authClient.getWebOptions() returns a weboptions object
        %  containing an Authorization header field with value Bearer <TOKEN>
        
            authField = matlab.net.http.field.AuthorizationField(...
                'Authorization', sprintf('Bearer %s', obj.AccessToken));
        end

        function refreshToken(obj)
            if ~ismissing(obj.RefreshToken_)
                obj.updateTokenFromRefreshToken()
            else
                obj.fetchToken()
            end
        end
    end

    methods (Access = private)
        function fetchToken(obj)
        % fetchToken - Fetch token using interactive Authorization Code flow
            
            codeVerifier = obj.generateCodeVerifier();
            authorizationUrl = obj.createAuthorizationUrl(codeVerifier);
            
            message = "Redirecting to web browser to authorize...";
            f = msgbox(message, "Authorizing...");
            reformatMessageBoxBeforeRedirecting(f)
            pause(1)
            delete(f);
            
            currentClipboardData = clipboard('paste');

            % Open in browser because url is for a web page
            web( char(authorizationUrl) )
            
            finished = false;
            while ~finished
                newClipboardData = clipboard('paste');
                if ~strcmp(newClipboardData, currentClipboardData)
                    finished = true;
                else
                    pause(0.3)
                end
            end


            % Prompt the user to input the authorization code
            authCode = inputdlg(...
                'Enter the access code provided by Dropbox: ', ...
                'Enter Access Code', ...
                [1 55], ...
                {newClipboardData});

            if isempty(authCode)
                obj.handleError('Canceled Authorization Flow', 'User Canceled')
            end

            obj.getTokenFromAuthorizationCode(authCode{1}, codeVerifier)
        end

        function authorizationUrl = createAuthorizationUrl(obj, codeVerifier)
            codeChallenge = obj.computeCodeChallenge(codeVerifier);

            urlParams = [
                "response_type", "code", ...
                "token_access_type", "offline", ...
                "client_id", obj.DropboxAppClientID, ...
                "code_challenge", codeChallenge, ...
                "code_challenge_method", "S256" ...
            ];

            authorizationUrl = matlab.net.URI(obj.AUTH_URL, urlParams{:});
        end

        function getTokenFromAuthorizationCode(obj, authCode, codeVerifier)
        % getTokenFromAuthorizationCode - Exchange the authorization code for a token
            
            httpOptions = obj.getHttpOptionsForTokenRequest();

            requestData = matlab.net.QueryParameter(...
                "grant_type", "authorization_code", ...
                "code", authCode, ...
                "client_id", obj.DropboxAppClientID, ...
                "code_verifier", codeVerifier ...
                );
            requestData = string(requestData);

            try
                tokenResponse = webwrite(obj.TOKEN_URL, requestData, httpOptions);
                obj.processTokenResponse(tokenResponse)
            catch ME
                obj.handleError(ME, "Authorization failed")
            end
        end

        function updateTokenFromRefreshToken(obj)
        % updateTokenFromRefreshToken - Update access token using refresh token
            
            finished = false;
            numRetries = 0;

            while ~finished || numRetries > 10
                httpOptions = obj.getHttpOptionsForTokenRequest();
    
                requestData = matlab.net.QueryParameter(...
                    "grant_type", "refresh_token", ...
                    "refresh_token", obj.RefreshToken_, ...
                    "client_id", obj.DropboxAppClientID ...
                    );
                requestData = string(requestData);
    
                try
                    tokenResponse = webwrite(obj.TOKEN_URL, requestData, httpOptions);
                    obj.processTokenResponse(tokenResponse)
                    finished = true;
                catch ME
                    fprintf( [...
                        'Failed to refresh Dropbox Access token with ', ...
                        'following error: \n"%s" \nTrying again in 5 seconds...\n'] , ...
                        ME.message )
                    numRetries = numRetries + 1; 
                    pause(5)
                end
            end
        end
        
        function processTokenResponse(obj, tokenResponse)
            obj.AccessToken_ = tokenResponse.access_token;
            
            obj.AccessTokenExpiresAt = ...
                datetime("now") + seconds(tokenResponse.expires_in);

            if isfield(tokenResponse, 'refresh_token')
                obj.RefreshToken_ = tokenResponse.refresh_token;
                obj.saveRefreshToken()
            end
        end

        function httpOptions = getHttpOptionsForTokenRequest(~)
            httpOptions = weboptions(...
                'RequestMethod', 'post', ...
                'MediaType', 'application/x-www-form-urlencoded');
        end

        function loadRefreshTokenFromPreviousSession(obj)
            secretName = 'DropboxApiRefreshToken';
            if isenv(secretName)
                obj.RefreshToken_ = getenv(secretName);
            elseif ispref('DropboxApiMATLAB', secretName)
                obj.RefreshToken_ = getpref('DropboxApiMATLAB', secretName);
            end
        end

        function saveRefreshToken(obj)
            secretName = 'DropboxApiRefreshToken';
            setpref('DropboxApiMATLAB', secretName, obj.RefreshToken_);
        end

        function resetRefreshToken(~)
            secretName = 'DropboxApiRefreshToken';
            if ispref('DropboxApiMATLAB', secretName)
                rmpref('DropboxApiMATLAB', secretName);
            end
        end
    end

    methods (Static)
        function obj = instance(clientId)
        % instance - Return a singleton instance of the AuthenticationClient

        %   Note: to achieve persistent singleton instance that survives a 
        %   clear all statement, the singleton instance is stored in the 
        %   graphics root object's appdata. 
        %   Open question: Are there better ways to do this?

            arguments
                clientId (1,1) string = missing
            end

            className = string( mfilename('class') );
            SINGLETON_NAME = eval( className + "." + "SINGLETON_NAME" );

            authClientObject = getappdata(0, SINGLETON_NAME);

            if ~isempty(authClientObject) && isa(authClientObject, className) && isvalid(authClientObject) 
                % Singleton instance is valid
            else % Construct the client if singleton instance is not present
                authClientObject = feval(className, clientId);
                setappdata(0, SINGLETON_NAME, authClientObject)
            end

            % - Return the instance
            obj = authClientObject;
        end

        function obj = reset(clientId)
                   
            arguments
                clientId (1,1) string = missing
            end

            className = string( mfilename('class') );
            SINGLETON_NAME = eval( className + "." + "SINGLETON_NAME" );

            if isappdata(0, SINGLETON_NAME)
                authClientObject = getappdata(0, SINGLETON_NAME);
                if ~isempty(authClientObject)
                    authClientObject.resetRefreshToken()
                    delete(authClientObject)
                    rmappdata(0, SINGLETON_NAME)
                end
            end

            obj = dropbox.internal.AuthorizationClient.instance(clientId);
        end
    end

    methods (Static)
        function codeVerifier = generateCodeVerifier()
            % Generate a random string
            codeVerifier = matlab.lang.internal.uuid() + matlab.lang.internal.uuid();
            codeVerifier = regexprep(codeVerifier, '-', ''); % Remove hyphens
        end

        function codeChallenge = computeCodeChallenge(codeVerifier)
            codeChallenge = base64urlencode(sha256(codeVerifier)); % private functions
        end
        
        function verifyCodeChallengeComputation()
            % https://www.authlete.com/developers/pkce/#24-code-challenge-method
            codeVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
            expectedCodeChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM";
            codeChallenge = dropbox.internal.AuthorizationClient.computeCodeChallenge(codeVerifier);
            assert(strcmp(codeChallenge, expectedCodeChallenge))
        end
    end

    methods (Static, Access = private)
        function handleError(ME, titleMessage)
            errordlg(ME.message, titleMessage);
            throwAsCaller(ME);
        end
    end
end

function reformatMessageBoxBeforeRedirecting(hFigure)
    hFigure.Position = hFigure.Position + [-50, 0, 100,14];
    hFigure.Children(1).Visible = 'off';
    hFigure.Children(1).FontSize = 14;
    centerHorizontally(hFigure, hFigure.Children(1) )
    hFigure.Children(2).Children(1).FontSize = 14;
    hFigure.Children(2).Children(1).Position(2) = hFigure.Children(2).Children(1).Position(2)+5;
    centerHorizontally(hFigure, hFigure.Children(2).Children(1) )
end

function centerHorizontally(hFigure, component)
    W = hFigure.Position(3);
    componentPosition = component.Position;
    if numel(componentPosition)==3
        componentPosition(3:4) = component.Extent(3:4);
    end
    
    xLeft = W/2 - componentPosition(3)/2;
    component.Position(1)=xLeft;
end
