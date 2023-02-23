# PlatformAccessController

Abstract contract from which platform contracts with admin function are inherited.

Contains modifier that checks whether sender is platform admin, use platform admin panel. All platform contracts with admin functionality must inherit from it, the admin panel that is transmitted during deployment should be the same for everyone.