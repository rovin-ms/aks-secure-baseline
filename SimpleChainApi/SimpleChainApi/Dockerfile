#See https://aka.ms/containerfastmode to understand how Visual Studio uses this Dockerfile to build your images for faster debugging.

FROM mcr.microsoft.com/dotnet/aspnet:5.0 AS base
WORKDIR /app
EXPOSE 80

FROM mcr.microsoft.com/dotnet/sdk:5.0 AS build
WORKDIR /src
COPY ["SimpleChainApi/SimpleChainApi.csproj", "SimpleChainApi/"]
RUN dotnet restore "SimpleChainApi/SimpleChainApi.csproj"
COPY . .
WORKDIR "/src/SimpleChainApi"
RUN dotnet build "SimpleChainApi.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "SimpleChainApi.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "SimpleChainApi.dll"]