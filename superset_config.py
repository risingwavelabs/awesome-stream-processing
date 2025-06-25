
AUTH_TYPE = AUTH_PUBLIC

AUTH_USER_REGISTRATION_ROLE = "Gamma"

from superset.security import SupersetSecurityManager
class PublicSecurityManager(SupersetSecurityManager):
    def auth_user_oidc(self, userinfo):
        return None
CUSTOM_SECURITY_MANAGER = PublicSecurityManager