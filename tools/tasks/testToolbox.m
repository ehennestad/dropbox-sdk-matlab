function testToolbox(varargin)
    projectRootDirectory = dropboxtools.projectdir();
    matbox.tasks.testToolbox(projectRootDirectory, varargin{:})
end