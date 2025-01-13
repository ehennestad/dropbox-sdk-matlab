    classdef MultiPartFileProvider < matlab.net.http.io.ContentProvider
        properties
            FileID double
        end

        properties (SetAccess = immutable)
            TotalBytes
            ChunkSize
        end

        properties 
            TotalCount = 0
            CurrentCount = 0
        end
 
        methods
            function obj = MultiPartFileProvider(name, totalBytes, chunkSize)
                obj.FileID = fopen(name);
                obj.TotalBytes = totalBytes;
                obj.ChunkSize = chunkSize;
            end
 
            function [data, stop] = getData(obj, requestedLength)
                allowedCount = obj.ChunkSize - obj.CurrentCount;
                if requestedLength > allowedCount
                    bytesToRead = allowedCount;
                else
                    bytesToRead = requestedLength;
                end

                [data, thisCount] = fread(obj.FileID, bytesToRead, '*uint8');

                obj.CurrentCount = obj.CurrentCount + thisCount;
                obj.TotalCount = obj.TotalCount + thisCount;

                stop = thisCount < requestedLength;
            end

            function resetCount(obj)
                obj.CurrentCount = 0;
            end

            function delete(obj)
                if ~isempty(obj.FileID)
                    fclose(obj.FileID);
                    obj.FileID = [];
                end
            end
        end

        methods (Access = protected)
            function tf = reusable(obj)
                tf = true;
            end
        end
    end