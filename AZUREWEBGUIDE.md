# Deploy SSOAzureSql to Azure App Service from GitHub

This guide deploys the app from:

```text
https://github.com/tomasgendron/SSOAzureSql.git
```

The recommended Azure shape is:

```text
Azure App Service on Linux
GitHub Actions deployment
React built into static files
FastAPI serving both the API and React app
Azure SQL accessed by App Service managed identity
Microsoft Entra ID used for SSO
```

## Current Azure Values

```text
Tenant ID: b7cb14b9-dc5c-44fe-a920-7e6bb7e310a6
Client ID: 57694959-05d4-412a-bf3a-4c16ff1f9828
SQL server: sql-sso-crud-dev-6931936.database.windows.net
Database: sqldb-crud-dev
```

Use your actual App Service name wherever this guide says:

```text
sso-azure-sql-crud
```

If that name is taken, choose a unique name and replace it everywhere.

## 1. Prepare The Repo For Production Hosting

The local development setup uses Vite for the React frontend and FastAPI for the backend. In Azure App Service, use one web app: build React into `dist`, then let FastAPI serve both `/api/*` and the React static app.

Before deploying, the repo should have:

```text
api/main.py
api/requirements.txt
package.json
vite.config.js
src/
```

The production FastAPI app needs to serve the frontend build output. Add this to `api/main.py` after all `/api/...` routes:

```python
from pathlib import Path

from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

BASE_DIR = Path(__file__).resolve().parent.parent
DIST_DIR = BASE_DIR / "dist"

if DIST_DIR.exists():
    app.mount("/assets", StaticFiles(directory=DIST_DIR / "assets"), name="assets")

    @app.get("/{full_path:path}")
    def serve_react_app(full_path: str):
        requested_path = DIST_DIR / full_path
        if requested_path.is_file():
            return FileResponse(requested_path)
        return FileResponse(DIST_DIR / "index.html")
```

Important: this catch-all route must come after the API routes, otherwise it can swallow `/api/...`.

Also make sure production frontend API calls use same-origin `/api`. In `src/api.js`, this should be true:

```javascript
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL ?? "";
```

For production, do not set `VITE_API_BASE_URL`. The browser will call:

```text
https://your-app-name.azurewebsites.net/api/...
```

## 2. Add A GitHub Actions Workflow

Create this file:

```text
.github/workflows/azure-webapp.yml
```

Use this workflow:

```yaml
name: Build and deploy SSO Azure SQL app

on:
  push:
    branches:
      - main
  workflow_dispatch:

env:
  AZURE_WEBAPP_NAME: sso-azure-sql-crud
  PYTHON_VERSION: "3.13"
  NODE_VERSION: "22"

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: npm

      - name: Build React frontend
        run: |
          npm ci
          npm run build

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}

      - name: Install Python dependencies into package
        run: |
          python -m pip install --upgrade pip
          pip install -r api/requirements.txt --target=".python_packages/lib/site-packages"

      - name: Package app
        run: |
          zip -r release.zip api dist .python_packages

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: app
          path: release.zip

  deploy:
    runs-on: ubuntu-latest
    needs: build
    permissions:
      id-token: write
      contents: read

    steps:
      - name: Download artifact
        uses: actions/download-artifact@v4
        with:
          name: app

      - name: Login to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to Azure Web App
        uses: azure/webapps-deploy@v3
        with:
          app-name: ${{ env.AZURE_WEBAPP_NAME }}
          package: release.zip
```

This workflow uses OpenID Connect instead of a publish profile. That is the cleaner Azure/GitHub setup, but it requires a federated credential in Entra ID.

## 3. Create The Azure App Service

In Azure Portal:

```text
https://portal.azure.com
```

Go to:

```text
App Services -> Create -> Web App
```

Use:

```text
Resource Group: rg-sql-sso-crud-dev
Name: sso-azure-sql-crud
Publish: Code
Runtime stack: Python 3.13
Operating System: Linux
Region: same or near your Azure SQL database
Pricing plan: Basic B1 or Free F1 for testing
```

Click:

```text
Review + create -> Create
```

After it is created, open the App Service.

## 4. Configure App Service Startup Command

Go to:

```text
App Service -> Configuration -> General settings
```

Set **Startup Command**:

```text
python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

Click:

```text
Save
```

Azure App Service forwards public traffic to the process running inside the container.

## 5. Add App Service Environment Variables

Go to:

```text
App Service -> Environment variables
```

Add these application settings:

```text
AZURE_TENANT_ID=b7cb14b9-dc5c-44fe-a920-7e6bb7e310a6
AZURE_CLIENT_ID=57694959-05d4-412a-bf3a-4c16ff1f9828
AZURE_SQL_SERVER=sql-sso-crud-dev-6931936.database.windows.net
AZURE_SQL_DATABASE=sqldb-crud-dev
AZURE_SQL_ODBC_DRIVER=ODBC Driver 18 for SQL Server
ALLOWED_ORIGINS=https://sso-azure-sql-crud.azurewebsites.net
USER_ROLE=User
ADMIN_ROLE=Admin
PYTHONPATH=/home/site/wwwroot/.python_packages/lib/site-packages
SCM_DO_BUILD_DURING_DEPLOYMENT=false
```

Only add `AZURE_MANAGED_IDENTITY_CLIENT_ID` if the web app itself has a user-assigned managed identity attached. Leave it absent for the normal system-assigned identity case.

Click:

```text
Apply
```

Then restart the App Service.

## 6. Enable Managed Identity

Go to:

```text
App Service -> Identity
```

Under **System assigned**:

```text
Status: On
```

Click:

```text
Save
```

Azure creates an Entra service principal with the same name as the App Service.

## 7. Grant The App Service Access To Azure SQL

Open your Azure SQL database:

```text
SQL databases -> sqldb-crud-dev -> Query editor
```

Sign in as the Microsoft Entra SQL admin.

Run this SQL, replacing the name if your App Service has a different name:

```sql
CREATE USER [sso-azure-sql-crud] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [sso-azure-sql-crud];
ALTER ROLE db_datawriter ADD MEMBER [sso-azure-sql-crud];
```

If `CREATE USER` says the user already exists, run only the `ALTER ROLE` lines.

The backend will use `DefaultAzureCredential`. In Azure App Service, that resolves to the system-assigned managed identity.

## 8. Allow App Service Network Access To SQL

For simple development:

Go to:

```text
SQL server -> Networking
```

Set:

```text
Public network access: Selected networks
Allow Azure services and resources to access this server: Yes
```

This is the simplest way to let App Service reach Azure SQL.

For production, use a private endpoint or VNet integration instead of broadly allowing Azure services.

## 9. Add The Production Redirect URI

Go to:

```text
Microsoft Entra ID -> App registrations -> SQL SSO CRUD App -> Authentication
```

Under **Single-page application**, add:

```text
https://sso-azure-sql-crud.azurewebsites.net
```

Keep local redirect URIs too:

```text
http://localhost:5177
http://127.0.0.1:5177
```

Redirect URIs must match exactly. If your App Service name is different, use that exact hostname.

## 10. Confirm App Roles And Assignment

Go to:

```text
Microsoft Entra ID -> App registrations -> SQL SSO CRUD App -> App roles
```

Confirm these roles exist and are enabled:

```text
User
Admin
```

Then go to:

```text
Enterprise applications -> SQL SSO CRUD App -> Users and groups
```

Assign your account:

```text
Role: Admin
```

For development, `Admin` is enough. The app treats `Admin` as also having read access.

## 11. Create Azure Login For GitHub Actions

The GitHub workflow uses OIDC. You need an Entra app registration or managed identity that GitHub Actions can use to deploy to Azure.

### Option A: Use Azure Portal Deployment Center

This is easiest.

Go to:

```text
App Service -> Deployment Center
```

Choose:

```text
Source: GitHub
Organization: tomasgendron
Repository: SSOAzureSql
Branch: main
Authentication type: User-assigned identity or OpenID Connect if offered
```

Azure can create the GitHub Actions workflow and identity wiring for you.

If Azure creates its own workflow, compare it with the workflow in this guide and keep the parts specific to this app:

```text
npm ci
npm run build
pip install -r api/requirements.txt --target=".python_packages/lib/site-packages"
Startup command: python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

### Option B: Configure OIDC Manually

Create an Entra app registration for GitHub deploys:

```text
Microsoft Entra ID -> App registrations -> New registration
```

Use:

```text
Name: github-sso-azure-sql-deploy
Supported account types: Single tenant
```

Copy:

```text
Application/client ID
Directory/tenant ID
```

Give it permission to deploy the App Service:

```text
Resource group -> Access control (IAM) -> Add role assignment
Role: Website Contributor
Members: github-sso-azure-sql-deploy
```

Add a federated credential:

```text
App registration -> Certificates & secrets -> Federated credentials -> Add credential
```

Use:

```text
Federated credential scenario: GitHub Actions deploying Azure resources
Organization: tomasgendron
Repository: SSOAzureSql
Entity type: Branch
Branch: main
Name: github-main-sso-azure-sql
```

In GitHub, add repository secrets:

```text
GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret
```

Add:

```text
AZURE_CLIENT_ID=<client ID of github-sso-azure-sql-deploy>
AZURE_TENANT_ID=b7cb14b9-dc5c-44fe-a920-7e6bb7e310a6
AZURE_SUBSCRIPTION_ID=<your Azure subscription ID>
```

Do not use the SQL SSO app client ID for deployment unless you intentionally gave that app deployment permissions. It is cleaner to keep the user-facing SSO app registration separate from the GitHub deployment identity.

## 12. Deploy From GitHub

Commit and push the production changes:

```powershell
git add .
git commit -m "Add Azure App Service deployment support"
git push origin main
```

Then go to:

```text
GitHub -> tomasgendron/SSOAzureSql -> Actions
```

Open the workflow run:

```text
Build and deploy SSO Azure SQL app
```

Wait for both jobs:

```text
build
deploy
```

to finish successfully.

## 13. Test The Deployed App

Open:

```text
https://sso-azure-sql-crud.azurewebsites.net
```

Expected flow:

```text
1. App loads
2. Click Sign in
3. Microsoft login appears
4. You sign in
5. App shows Items page
6. Create/update/delete records
7. Data persists in Azure SQL
```

## 14. Common Errors

### AADSTS50011 redirect URI mismatch

The redirect URI sent by the app does not exactly match Entra configuration.

Fix:

```text
App registrations -> SQL SSO CRUD App -> Authentication
```

Add the exact URL shown in the error, for example:

```text
https://sso-azure-sql-crud.azurewebsites.net
```

### 403 User or Admin role required

Your signed-in account does not have the expected app role.

Fix:

```text
Enterprise applications -> SQL SSO CRUD App -> Users and groups
```

Assign yourself:

```text
Admin
```

Then sign out and sign back in.

### SQL login/user error

The App Service managed identity does not have a database user.

Fix:

```sql
CREATE USER [sso-azure-sql-crud] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [sso-azure-sql-crud];
ALTER ROLE db_datawriter ADD MEMBER [sso-azure-sql-crud];
```

### ODBC Driver error

The App Service image must have the Microsoft ODBC driver available. Azure App Service Python Linux images commonly include Microsoft SQL connectivity support, but if this fails, use a custom container or adjust the app to use a driver available in the image.

### App shows default Azure page

The deployment did not place the app files where App Service expects, or startup command is wrong.

Check:

```text
App Service -> Configuration -> General settings -> Startup Command
```

Expected:

```text
python -m uvicorn api.main:app --host 0.0.0.0 --port 8000
```

Also check:

```text
App Service -> Log stream
```

## 15. Useful Azure Pages

```text
App Service -> Deployment Center
App Service -> Configuration
App Service -> Identity
App Service -> Log stream
App Service -> Diagnose and solve problems
SQL server -> Networking
SQL database -> Query editor
Microsoft Entra ID -> App registrations
Microsoft Entra ID -> Enterprise applications
```

## References

- Microsoft Learn: Deploy Python apps to Azure App Service with GitHub Actions
  `https://learn.microsoft.com/en-us/azure/developer/python/python-web-app-github-actions-app-service`
- Microsoft Learn: Deploy FastAPI to Azure App Service
  `https://learn.microsoft.com/en-us/azure/app-service/quickstart-python`
- Microsoft Learn: App Service continuous deployment
  `https://learn.microsoft.com/en-us/azure/app-service-web/app-service-continuous-deployment`
