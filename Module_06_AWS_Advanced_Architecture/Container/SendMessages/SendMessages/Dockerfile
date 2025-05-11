# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project files and restore dependencies
COPY ["SendMessages.csproj", "."]
RUN dotnet restore "SendMessages.csproj"

# Copy the rest of the application code
COPY . .

# Publish the application
RUN dotnet publish "SendMessages.csproj" -c Release -o /app/publish /p:PublishReadyToRun=true

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Copy the published output from the build stage
COPY --from=build /app/publish ./

# Set the entry point for the application
ENTRYPOINT ["dotnet", "SendMessages.dll"]