.. _pdo_dbh_t:

pdo_dbh_t definition
====================

All fields should be treated as read-only by the driver, unless explicitly
stated otherwise.

.. code-block:: c

    /* represents a connection to a database */
    struct _pdo_dbh_t {
        /* driver specific methods */
        struct pdo_dbh_methods *methods;

The driver *must* set this during
``SKEL_handle_factory``.

.. code-block:: c

        /* driver specific data */
        void *driver_data;

This item is for use by the driver; the intended usage is to store a
pointer (during ``SKEL_handle_factory``) 
to whatever instance data is required to maintain a connection to
the database.

.. code-block:: c

        /* credentials */
        char *username, *password;

The username and password that were passed into the PDO constructor.
The driver should use these values when it initiates a connection to the
database.

.. code-block:: c

        /* if true, then data stored and pointed at by this handle must all be
         * persistently allocated */
        unsigned is_persistent:1;

If this is set to 1, then any data that is referenced by the
dbh, including whatever structure your driver allocates,
*MUST* be allocated persistently.  This is easy to
achieve; rather than using the usual ``emalloc`` simply
use ``pemalloc`` and pass the value of this flag as the
last parameter.  Failure to use the appropriate kind of memory can lead
to serious memory faults, resulting (in the best case) a hard crash, and
in the worst case, an exploitable memory problem.

If, for whatever reason, your driver is not suitable to run persistently,
you *MUST* check this flag in your
``SKEL_handle_factory`` and raise an appropriate error.

.. code-block:: c

        /* if true, driver should act as though a COMMIT were executed between
         * each executed statement; otherwise, COMMIT must be carried out manually */
        unsigned auto_commit:1;

You should check this value in your ``SKEL_handle_doer``
and ``SKEL_stmt_execute`` functions; if it evaluates to
true, you must attempt to commit the query now.  Most database
implementations offer an auto-commit mode that handles this automatically.

.. code-block:: c

        /* if true, the driver requires that memory be allocated explicitly for
        * the columns that are returned */
        unsigned alloc_own_columns:1;

If your database client library API operates by fetching data into a
caller-supplied buffer, you should set this flag to 1 during your
``SKEL_handle_factory``.  When set, PDO will call your
``SKEL_stmt_describer`` earlier than it would
otherwise.  This early call allows you to determine those buffer sizes
and issue appropriate calls to the database client library.

If your database client library API simply returns pointers to its own
internal buffers for you to copy after each fetch call, you should leave
this value set to 0.

.. code-block:: c

        /* if true, commit or rollBack is allowed to be called */
        unsigned in_txn:1;                  

        /* max length a single character can become after correct quoting */
        unsigned max_escaped_char_length:3;

If your driver doesn't support native prepared statements
(``supports_placeholders`` is set to
``PDO_PLACEHOLDER_NONE``), you must set
this value to the maximum length that can be taken up by a single
character when it is quoted by your
``SKEL_handle_quoter`` function.  This value is used to
calculate the amount of buffer space required when PDO executes the
statement.

.. code-block:: c

        /* data source string used to open this handle */
        const char *data_source;

This holds the value of the DSN that was passed into the PDO
constructor.  If your driver implementation needed to modify the DSN for
whatever reason, it should update this member during
``SKEL_handle_factory``.  Modifying this member should
be avoided.  If you do change it, you must ensure that
``data_source_len`` is also correct.

.. code-block:: c

        unsigned long data_source_len;

        /* the global error code. */
        pdo_error_type error_code;

Whenever an error occurs during a call to one of your driver methods,
you should set this member to the SQLSTATE code that best describes the
error and return an error.  In this HOW-TO, the suggested practice is to
call ``SKEL_handle_error`` when an error is detected,
and have it set the error code.

.. code-block:: c

        enum pdo_case_conversion native_case, desired_case;
    };

Your driver should set this during
``SKEL_handle_factory``; the value should reflect how
the database returns the names of the columns in result sets.  If the
name matches the case that was used in the query, set it to
``PDO_CASE_NATURAL`` (this is actually the default).
If the column names are always returned in upper case, set it to
``PDO_CASE_UPPER``.  If the column names are always
returned in lower case, set it to ``PDO_CASE_LOWER``.
The value you set is used to determine if PDO should perform case
folding when the user sets the ``PDO_ATTR_CASE``
attribute.
