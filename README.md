<a href="/resources/images/toolbox_image.png">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="/resources/images/toolbox_image.png">
    <source media="(prefers-color-scheme: light)" srcset="/resources/images/toolbox_image.png">
    <img alt="Dropbox-API-Client-logo" src="/resources/images/toolbox_image.png" title="Dropbox API" align="right" height="70"​>
  </picture>
</a>

# Dropbox API Client - Upload and Download Files

<h4 align="center">Class-based Dropbox File API-Client for uploading and downloading files from Dropbox with progress display.</h4>

<h4 align="center">
  <a href="https://github.com/ehennestad/dropbox-sdk-matlab/releases/latest">
    <img src="https://img.shields.io/github/v/release/ehennestad/dropbox-sdk-matlab?label=version" alt="Version">
  </a>
  <a href="https://se.mathworks.com/matlabcentral/fileexchange/179054-dropbox-file-api-client-upload-and-download-files">
    <img src="https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg" alt="View Dropbox File API Client - Upload and Download Files on File Exchange">
  </a>
  <a href="https://codecov.io/gh/ehennestad/dropbox-sdk-matlab" >
   <img src="https://codecov.io/gh/ehennestad/dropbox-sdk-matlab/graph/badge.svg?token=Z2L1HGYAPV" alt="Codecov"/>  
  </a>
  <a href="https://github.com/ehennestad/dropbox-sdk-matlab/actions/workflows/run_tests.yml/badge.svg?branch=main">
   <img src="https://github.com/ehennestad/dropbox-sdk-matlab/actions/workflows/run_tests.yml/badge.svg?branch=main" alt="Run tests">
  </a>
  <a href="https://github.com/ehennestad/dropbox-sdk-matlab/security/code-scanning">
   <img src=".github/badges/code_issues.svg" alt="MATLAB Code Issues">
  </a>
</h4>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#features">Features</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#references">References</a>
</p>

<p align="center">
  <img width="745" alt="dropbox_download" src="https://github.com/user-attachments/assets/7154444f-a672-4dec-a1ca-3f5896dedd3e" />
</p>


## Installation
The Dropbox client can be installed from MATLAB's Addon manager or from the [FileExchange](https://se.mathworks.com/matlabcentral/fileexchange/179054-dropbox-file-api-client-upload-and-download-files).

## Getting Started
``` matlab
% Initialize the client
client = dropbox.DropboxApiClient();

% List contents of a folder
entries = client.listFolder("/MyFolder");
disp(entries);

% Upload a file
client.uploadFile("local_file.txt", "/DropboxFolder/file.txt");

% Download a file
client.downloadFile("/DropboxFolder/file.txt", "local_folder");

% Create a folder
client.createFolder("/NewFolder");

% Search for files
results = client.search("example");
disp(results);
```

The first time you create a client you will be redirected to Dropbox for secure login.

## Features

### Logging in
This API Client uses a Dropbox App for authenticating with Dropbox using a PKCE authorization flow. Users are redirected to Dropbox in the browser, and can secureley enter credentials to log in. The Dropbox app can read the user's account info as well as file metadata and has read and write access to files. It is also possible to use your own Dropbox app (details coming soon).

### Class methods
The client has the following methods:
 - uploadFile (Files up to 350GB, with progress monitor)
 - downloadFile (With progress monitor)
 - listFolder
 - createFolder
 - getMetadata
 - search
 - move
 - copy
 - getTemporaryDownloadLink
 - getTemporaryUploadLink

## Contributing
If you find bugs or missing features, please create an issue. PR's with suggested changes are of course also welcome! 
This Client is by no means complete, but should provide minimal functionality for working with files on Dropbox.

## References
Dropbox API Documentation: [Dropbox Developers](https://www.dropbox.com/developers/documentation/http/documentation)
