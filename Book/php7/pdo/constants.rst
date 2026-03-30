Constants
=========

.. _pdo_attributes:

Database and Statement Attributes
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PDO_ATTR_AUTOCOMMIT
    BOOL
    
    TRUE if autocommit is set, FALSE otherwise.
    
    ``dbh->auto_commit`` contains value. Processed by PDO directly.

PDO_ATTR_PREFETCH
    LONG
    
    Value of the prefetch size in drivers that support it.

PDO_ATTR_TIMEOUT
    LONG

    How long to wait for a db operation before timing out.

PDO_ATTR_ERRMODE
    LONG

    Processed and handled by PDO

PDO_ATTR_SERVER_VERSION
    STRING

    The "human-readable" string representing the
    Server/Version this driver is currently connected to.

PDO_ATTR_CLIENT_VERSION
    STRING
    
    The "human-readable" string representing the Client/Version this driver supports.

PDO_ATTR_SERVER_INFO
    STRING
    
    The "human-readable" description of the Server.

PDO_ATTR_CONNECTION_STATUS
    LONG
    
    Values not yet defined

PDO_ATTR_CASE
    LONG
    
    Processed and handled by PDO.

PDO_ATTR_CURSOR_NAME
    STRING

    String representing the name for a database cursor for use in
    "where current in <name>" SQL statements.

PDO_ATTR_CURSOR
    LONG

    PDO_CURSOR_FWDONLY
        Forward only cursor
    PDO_CURSOR_SCROLL
        Scrollable cursor

The values for the attributes above are all defined in terms of the Zend
API. The Zend API contains macros that can be used to convert a ``*zval`` to a
value. These macros are defined in the Zend header file, zend_API.h in the
Zend directory of your PHP build directory. Some of these attributes can be
used with the statement attribute handlers such as the PDO_ATTR_CURSOR and
PDO_ATTR_CURSOR_NAME. See the statement attribute handling functions for
more information.
