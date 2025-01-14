classdef DropboxApiClientTest < matlab.unittest.TestCase
    
    properties
        Client
        TestFolder = "/TestFolder"
    end
    
    methods(TestClassSetup)
        function setupTest(testCase)
            testCase.TestFolder = testCase.TestFolder + "/" + char(randi([65 90], 1, 5));

            testCase.Client = dropbox.DropboxApiClient();
            testCase.Client.createFolder(testCase.TestFolder);

            testCase.addTeardown(@delete, testCase.Client, testCase.TestFolder)
        end
    end
    
    methods(Test)
        function testAuthorizationFlow(testCase)
            % Test authorization client singleton
            client1 = dropbox.internal.AuthorizationClient.instance();
            client2 = dropbox.internal.AuthorizationClient.instance();
            testCase.verifyEqual(client1, client2, 'Should return same instance');
            
            % Test token expiry
            remainingTime = client1.TokenExpiresIn;
            testCase.verifyTrue(isduration(remainingTime), 'Should return datetime value');
        end

        function testContinuousSearch(testCase)
            % Create test content
            testCase.Client.createFolder(testCase.TestFolder + "/SearchTest1");
            testCase.Client.createFolder(testCase.TestFolder + "/SearchTest2");
            
            pause(2); % Give Dropbox time to index
            
            % Initial search
            [results, cursor] = testCase.Client.search("SearchTest", testCase.TestFolder, 'MaxResults', 1);
            testCase.verifyTrue(~isempty(results), 'Should return first result');
            testCase.verifyTrue(~isempty(cursor), 'Should return cursor for more results');
            
            % Continue search
            [moreResults, ~] = testCase.Client.continueSearch(cursor);
            testCase.verifyTrue(~isempty(moreResults), 'Should return more results');
        end

        function testDownloadContent(testCase)
            % Create and upload test file
            tempFile = [tempname '.txt'];
            fid = fopen(tempFile, 'w');
            fprintf(fid, 'Test content');
            fclose(fid);
            cleanupObj = onCleanup(@() delete(tempFile));
            
            remoteFile = testCase.TestFolder + "/download_test.txt";
            testCase.Client.uploadFile(tempFile, remoteFile);
            
            % Test direct content download
            content = testCase.Client.downloadFileContent(remoteFile);
            testCase.verifyEqual(char(transpose(content)), 'Test content');
        end

        function testProgressMonitor(testCase)
            % Create test file
            tempFile = [tempname '.txt'];
            fid = fopen(tempFile, 'w');
            fprintf(fid, 'Test content for progress monitor');
            fclose(fid);
            cleanupObj = onCleanup(@() delete(tempFile));
            
            % Create progress monitor
            monitor = dropbox.internal.DropboxMultiSessionUploadProgressMonitor(1000);
            %monitor.update(500); % 50% progress
            monitor.Value = 500;
            testCase.verifyEqual(monitor.PercentTransferred, 50);
            monitor.quit();
        end

        function testUploadAndDownload(testCase)
            % Create a temporary test file
            tempFile = [tempname '.txt'];
            fid = fopen(tempFile, 'w');
            fprintf(fid, 'Test content for upload');
            fclose(fid);
            cleanupObj = onCleanup(@() delete(tempFile));
            
            % Test upload
            remoteFile = testCase.TestFolder + "/test_upload.txt";
            testCase.Client.uploadFile(tempFile, remoteFile);
            
            % Test download
            downloadDir = tempname;
            mkdir(downloadDir);
            cleanupDirObj = onCleanup(@() rmdir(downloadDir, 's'));
            
            downloadedFile = testCase.Client.downloadFile(remoteFile, downloadDir);
            testCase.verifyTrue(isfile(downloadedFile), 'Downloaded file should exist');
            
            % Verify content
            content = fileread(downloadedFile);
            testCase.verifyEqual(content, 'Test content for upload');
        end

        function testUploadSessionWithLargeFile(testCase)
            % Create a temporary large file (>150MB to trigger multipart upload)
            tempFile = [tempname '.bin'];
            fid = fopen(tempFile, 'w');
            chunkSize = 1024 * 1024; % 1MB chunks
            chunk = uint8(rand(1, chunkSize) * 255);
            for i = 1:160 % Write 160MB
                fwrite(fid, chunk);
            end
            fclose(fid);
            cleanupObj = onCleanup(@() delete(tempFile));
            
            % Test multipart upload
            remoteFile = testCase.TestFolder + "/large_test_file.bin";
            testCase.Client.uploadFile(tempFile, remoteFile);
            
            % Verify file exists
            metadata = testCase.Client.getMetadata(remoteFile);
            testCase.verifyEqual(char(metadata.path_display), char(remoteFile));
        end

        function testTemporaryLinks(testCase)
            % Create test file
            tempFile = [tempname '.txt'];
            fid = fopen(tempFile, 'w');
            fprintf(fid, 'Test content');
            fclose(fid);
            cleanupObj = onCleanup(@() delete(tempFile));
            
            % Upload file
            remoteFile = testCase.TestFolder + "/link_test.txt";
            testCase.Client.uploadFile(tempFile, remoteFile);
            
            % Test download link
            downloadLink = testCase.Client.getTemporaryDownloadLink(remoteFile);
            testCase.verifyTrue(startsWith(downloadLink, 'https://'), 'Download link should be HTTPS URL');
            
            % Test upload link
            uploadLink = testCase.Client.getTemporaryUploadLink(remoteFile);
            testCase.verifyTrue(startsWith(uploadLink, 'https://'), 'Upload link should be HTTPS URL');
        end
        function testCreateFolder(testCase)
            newFolder = testCase.TestFolder + "/NewFolder";
            result = testCase.Client.createFolder(newFolder);
            testCase.verifyEqual(char(result.name), char("NewFolder"));
            testCase.verifyEqual(char(result.path_display), char(newFolder));
        end
        
        function testListFolder(testCase)
            % Create some test content
            testCase.Client.createFolder(testCase.TestFolder + "/ListTest");
            
            % Test listing
            entries = testCase.Client.listFolder(testCase.TestFolder);
            testCase.verifyTrue(~isempty(entries));
            
            % Verify folder exists in listing
            folderNames = getNamesFromEntries(entries);
            testCase.verifyTrue(any(folderNames == "ListTest"));
        end
        
        function testSearch(testCase)
            % Create test content
            testCase.Client.createFolder(testCase.TestFolder + "/SearchTest");
            
            pause(2); % Give Dropbox time to index the new folder

            % Test search
            [results, ~] = testCase.Client.search("SearchTest", testCase.TestFolder);
            testCase.verifyTrue(~isempty(results), 'Search results should not be empty');
            
            % Test search with options
            [results2, ~] = testCase.Client.search("SearchTest", testCase.TestFolder, ...
                'FilenameOnly', true, 'MaxResults', 50);
            testCase.verifyTrue(~isempty(results2), 'Search with options should return results');
        end
        
        function testMove(testCase)
            % Create test folder
            sourceFolder = testCase.TestFolder + "/MoveSource";
            destFolder = testCase.TestFolder + "/MoveDest";
            testCase.Client.createFolder(sourceFolder);
            
            % Test move
            result = testCase.Client.move(sourceFolder, destFolder);
            testCase.verifyEqual(char(result.metadata.path_display), char(destFolder));
            
            % Verify source no longer exists
            entries = testCase.Client.listFolder(testCase.TestFolder);
            folderNames = getNamesFromEntries(entries);
            testCase.verifyTrue(~any(folderNames == "MoveSource"));
            testCase.verifyTrue(any(folderNames == "MoveDest"));
        end
        
        function testCopy(testCase)
            % Create test folder
            sourceFolder = testCase.TestFolder + "/CopySource";
            destFolder = testCase.TestFolder + "/CopyDest";
            testCase.Client.createFolder(sourceFolder);
            
            % Test copy
            result = testCase.Client.copy(sourceFolder, destFolder);
            testCase.verifyEqual(char(result.metadata.path_display), char(destFolder));
            
            % Verify both source and destination exist
            entries = testCase.Client.listFolder(testCase.TestFolder);
            folderNames = getNamesFromEntries(entries);
            testCase.verifyTrue(any(folderNames == "CopySource"));
            testCase.verifyTrue(any(folderNames == "CopyDest"));
        end
        
        function testGetMetadata(testCase)
            % Create test folder
            testFolder = testCase.TestFolder + "/MetadataTest";
            testCase.Client.createFolder(testFolder);
            
            pause(3); % Give Dropbox time to index the new folder
            
            % Test get metadata
            result = testCase.Client.getMetadata(testFolder);
            testCase.verifyEqual(char(result.path_display), char(testFolder));
            testCase.verifyEqual(char(result.x_tag), 'folder');
        end
        
        
        function testTeamConfiguration(testCase)
            % Test team configuration setting
            testCase.Client.TeamConfiguration = "TeamSpace";
            testCase.verifyEqual(string(testCase.Client.TeamConfiguration), "TeamSpace");
            
            testCase.Client.TeamConfiguration = "TeamFolders";
            testCase.verifyEqual(string(testCase.Client.TeamConfiguration), "TeamFolders");
        end
        
        function testErrorHandling(testCase)
            % Test invalid folder path
            invalidPath = "/NonExistentFolder" + char(randi([65 90], 1, 10));
            
            try
                testCase.Client.getMetadata(invalidPath);
                testCase.verifyFail('Expected error was not thrown');
            catch ME
                testCase.verifyTrue(contains(ME.message, 'not_found'));
            end
        end
    end
end

function names = getNamesFromEntries(entries)
    if isstruct(entries)
        names = string({entries.name});
    elseif iscell(entries)
        names = cellfun(@(c) c.name, entries, 'UniformOutput', false);
    else
        error('Unexpected type')
    end
    names = string(names);
end
