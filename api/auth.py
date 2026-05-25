from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from .config import Settings, get_settings


bearer_scheme = HTTPBearer(auto_error=False)


def _roles_from_claims(claims: dict[str, Any]) -> set[str]:
    roles = claims.get("roles") or []
    if isinstance(roles, str):
        return {roles}
    return set(roles)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, Any]:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    try:
        jwks_client = PyJWKClient(settings.jwks_url)
        signing_key = jwks_client.get_signing_key_from_jwt(credentials.credentials)
        claims = jwt.decode(
            credentials.credentials,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.client_id,
            issuer=settings.issuer,
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Microsoft identity token",
        ) from exc

    claims["app_roles"] = _roles_from_claims(claims)
    return claims


def require_reader(
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, Any]:
    roles = user["app_roles"]
    if settings.user_role in roles or settings.admin_role in roles:
        return user
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="User or Admin role required",
    )


def require_admin(
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, Any]:
    if settings.admin_role in user["app_roles"]:
        return user
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Admin role required",
    )


def display_name(user: dict[str, Any]) -> str:
    return (
        user.get("preferred_username")
        or user.get("email")
        or user.get("name")
        or user.get("oid")
        or "unknown"
    )
