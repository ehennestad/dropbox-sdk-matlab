function packageToolbox(releaseType, versionString)
    arguments
        releaseType {mustBeTextScalar,mustBeMember(releaseType,["build","major","minor","patch","specific"])} = "build"
        versionString {mustBeTextScalar} = "";
    end
    projectRootDirectory = dropboxtools.projectdir();
    matbox.tasks.packageToolbox(projectRootDirectory, releaseType, versionString)
end