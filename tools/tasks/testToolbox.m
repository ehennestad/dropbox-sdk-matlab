function testToolbox(varargin)
    installMatBox()
    projectRootDirectory = dropboxtools.projectdir();
    matbox.tasks.testToolbox(projectRootDirectory, varargin{:})
end