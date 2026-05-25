# Microsoft SSO Azure SQL CRUD App

Modern React UI with Microsoft Entra sign-in and a FastAPI backend that connects to Azure SQL using Entra authentication.

## Azure Values

```text
Tenant ID: b7cb14b9-dc5c-44fe-a920-7e6bb7e310a6
Client ID: 57694959-05d4-412a-bf3a-4c16ff1f9828
SQL server: sql-sso-crud-dev-6931936.database.windows.net
Database: sqldb-crud-dev
```

## Required Azure Setup

Use the main Azure Portal for Azure resources:

```text
https://portal.azure.com
```

Use Microsoft Entra pages for identity resources such as users, groups, app registrations, and enterprise app assignments.

### 1. Create the Azure resource group

In Azure Portal:

```text
Resource groups -> Create
```

Use:

```text
Name: rg-sql-sso-crud-dev
Region: your preferred region
```

This is the Azure container that holds the SQL server and database. It is different from a Microsoft Entra security group.

### 2. Create Entra security groups

In Microsoft Entra ID:

```text
Groups -> New group
```

Create these security groups:

```text
SQLApp-DB-Admins
SQLApp-Users
SQLApp-Admins
```

For each group:

```text
Group type: Security
Membership type: Assigned
Owners: your account
Members: your account
```

For a single-user dev setup, assigning your own account directly also works. Groups are cleaner when more people are added later.

### 3. Create the Azure SQL server and database

In Azure Portal:

```text
Azure SQL -> Create -> SQL database
```

Use:

```text
Resource group: rg-sql-sso-crud-dev
Database name: sqldb-crud-dev
Server: create new
Server name: sql-sso-crud-dev-6931936
Authentication: Microsoft Entra authentication, or mixed auth if the portal requires it
```

On the SQL server resource, configure the Microsoft Entra admin:

```text
SQL server -> Microsoft Entra ID / Active Directory admin
Admin: SQLApp-DB-Admins
```

Networking for local development:

```text
SQL server -> Networking
Public network access: Selected networks
Add your client IPv4 address
Allow Azure services and resources to access this server: Yes
```

Production should use tighter networking, such as private endpoints or restricted app outbound access.

### 4. Create the app registration

In Microsoft Entra ID:

```text
App registrations -> New registration
```

Use:

```text
Name: SQL SSO CRUD App
Supported account types: Single tenant
Platform: Single-page application
Redirect URI: http://localhost:5177
```

Copy these values into the app config:

```text
Application/client ID
Directory/tenant ID
```

This repo currently uses:

```text
Tenant ID: b7cb14b9-dc5c-44fe-a920-7e6bb7e310a6
Client ID: 57694959-05d4-412a-bf3a-4c16ff1f9828
```

### 5. Add app roles

In:

```text
Microsoft Entra ID -> App registrations -> SQL SSO CRUD App -> App roles
```

Create and enable:

```text
Display name: User
Value: User
Allowed member types: Users/Groups
```

```text
Display name: Admin
Value: Admin
Allowed member types: Users/Groups
```

Then assign users or groups in:

```text
Enterprise applications -> SQL SSO CRUD App -> Users and groups
```

For dev, assign your account to:

```text
Admin
```

`Admin` is enough because the app treats `Admin` as including read access.

### 6. Configure redirect URI

In:

```text
Microsoft Entra ID -> App registrations -> SQL SSO CRUD App -> Authentication
```

Under **Single-page application**, add:

```text
http://localhost:5177
```

Optional:

```text
http://127.0.0.1:5177
```

Use `http://localhost:5177` in the browser. Redirect URIs must match exactly.

### 7. Create the SQL schema

Open the Azure SQL database query editor and sign in as the Microsoft Entra SQL admin. Run:

```sql
CREATE TABLE dbo.Items (
    Id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Items PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(1000) NULL,
    Status NVARCHAR(40) NOT NULL CONSTRAINT DF_Items_Status DEFAULT 'Open',
    CreatedBy NVARCHAR(256) NOT NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Items_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedBy NVARCHAR(256) NULL,
    UpdatedAt DATETIME2 NULL
);

CREATE INDEX IX_Items_Status ON dbo.Items(Status);
CREATE INDEX IX_Items_CreatedAt ON dbo.Items(CreatedAt DESC);
```

The same SQL is also in `sql/schema.sql`.

### 8. Grant SQL permissions

For local development, the backend connects to Azure SQL using the identity from:

```powershell
az login
```

Check that identity with:

```powershell
az account show --query "{user:user.name, tenant:tenantId, subscription:name}" -o table
```

Then grant that signed-in identity database access:

```sql
CREATE USER [your.email@domain.com] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your.email@domain.com];
ALTER ROLE db_datawriter ADD MEMBER [your.email@domain.com];
```

Or grant access through the admin group:

```sql
CREATE USER [SQLApp-Admins] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [SQLApp-Admins];
ALTER ROLE db_datawriter ADD MEMBER [SQLApp-Admins];
```

Make sure your account is a member of `SQLApp-Admins`.

## Local Setup

Install the frontend:

```powershell
npm install
```

Create the backend virtual environment and install dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r api\requirements.txt
```

Install the Microsoft ODBC driver if it is not already installed:

[Download ODBC Driver 18 for SQL Server](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)

Sign in to Azure CLI:

```powershell
az login
```

Copy backend env:

```powershell
Copy-Item api\.env.example api\.env
```

Run the backend:

```powershell
.\.venv\Scripts\python -m uvicorn api.main:app --reload --port 8007
```

Run the frontend in another terminal:

```powershell
npm run dev
```

Open:

```text
http://localhost:5177
```

## Important Note

The browser does not connect directly to Azure SQL. React signs the user in and calls the FastAPI backend. The backend validates the Microsoft token and performs database operations using Entra authentication.
