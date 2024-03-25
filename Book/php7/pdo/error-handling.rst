.. _pdo_error_handling:

Error handling
==============

Error handling is implemented using a hand-shaking protocol between 
PDO and the database driver code. The database driver code
signals PDO that an error has occurred via a failure
(``0``) return from any of the interface functions. If a zero
is returned, set the field ``error_code`` in the control
block appropriate to the context (either the pdo_dbh_t or pdo_stmt_t block).
In practice, it is probably a good idea to set the field in both blocks to
the same value to ensure the correct one is getting used.

The error_mode field is a six-byte field containing a 5 character ASCIIZ
SQLSTATE identifier code. This code drives the error message process. The
SQLSTATE code is used to look up an error message in the internal PDO error
message table (see pdo_sqlstate.c for a list of error codes and their
messages). If the code is not known to PDO, a default
"Unknown Message" value will be used.

In addition to the SQLSTATE code and error message, PDO will
call the driver-specific fetch_err() routine to obtain supplemental data
for the particular error condition. This routine is passed an array into
which the driver may place additional information. This array has slot
positions assigned to particular types of supplemental info:

#.  A native error code. This will frequently be an error code obtained
    from the database API.

#.  A descriptive string. This string can contain any additional
    information related to the failure. Database drivers typically include
    information such as an error message, code location of the failure, and
    any additional descriptive information the driver developer feels
    worthy of inclusion. It is generally a good idea to include all
    diagnostic information obtainable
    from the database interface at the time of the failure. For
    driver-detected errors (such as memory allocation problems), the driver
    developer can define whatever error information that seems appropriate.
