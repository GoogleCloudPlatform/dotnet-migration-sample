# escape=`

FROM mcr.microsoft.com/dotnet/framework/sdk:4.8-windowsservercore-ltsc2019 AS build
WORKDIR /source
COPY . /source

RUN msbuild ContosoUniversity.sln /t:restore /p:RestorePackagesConfig=true
RUN msbuild /p:Configuration=Release `
	/t:WebPublish `
	/p:WebPublishMethod=FileSystem `
	/p:publishUrl=C:\Deploy

FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2019 AS runtime
COPY --from=build /deploy /inetpub/wwwroot

EXPOSE 80